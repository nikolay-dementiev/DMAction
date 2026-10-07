#!/bin/bash
#
# Compares the public interface of the library with the committed baseline.
#
#   Scripts/check-api.sh               compare, exit 1 on any difference
#   Scripts/check-api.sh --update      rewrite the baseline from the current sources
#   Scripts/check-api.sh --self-test   run the normalisation on the cases in
#                                      Fixtures/API/normalizer, no compiler needed
#
# Any difference fails. A removed or changed line is a break of the public contract.
# An added line is new public API: run with --update and commit the baseline together
# with the change, so the whole API delta is readable in the diff of one file.
#
# The interface text depends on the compiler and the SDK. CI runs this check on one
# pinned Xcode; after a toolchain change the baseline may need --update with no API change.
#
# Exit codes: 0 the same interface, 1 a different interface, 2 the check could not run.

set -euo pipefail

# ==== Settings of this repository =======================================================
# The packages DMAction, DMVariableBlurView and DMUnLoader share this script. Only this
# block differs between them. Everything below the end marker is identical in the three:
# a change there is made in the copy of DMVariableBlurView and synced to the other two.

# The module whose public interface is checked.
MODULE="DMAction"
# The directory the manifest compiles for that module, relative to the repository root.
SOURCE_DIR="Sources/DMAction"
# The language mode and the upcoming features the manifest sets for the module.
SWIFT_FLAGS=(-swift-version 6 -enable-upcoming-feature ExistentialAny)
# "yes" to emit the interface with library evolution, "no" without it.
LIBRARY_EVOLUTION="yes"
# Modules of package dependencies that the module imports, compiled first and in this
# order. One entry per module: "<module>|<source directory>|<compiler flags>", where the
# flags mirror the manifest of the dependency, including its -package-name.
DEPENDENCIES=()
# A command run from the repository root before anything is compiled, for example
# (swift package resolve) to check out the dependencies. Empty: nothing to prepare.
PREPARE=()

# ==== End of the settings ===============================================================

# An array that a settings block leaves out, or leaves empty, is an empty array from here
# on. Bash 3.2, the version macOS ships, treats an empty array as unbound under set -u.
SWIFT_FLAGS=(${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"})
DEPENDENCIES=(${DEPENDENCIES[@]+"${DEPENDENCIES[@]}"})
PREPARE=(${PREPARE[@]+"${PREPARE[@]}"})

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="$ROOT/Fixtures/API/public-interface.txt"
WORK="$ROOT/.build/check-api"
INTERFACE="$WORK/$MODULE.swiftinterface"
CURRENT="$WORK/public-interface.txt"

mkdir -p "$WORK"

# Header comments carry the compiler version and flags; imports are not API; an empty
# line only marks where a source file ended. The compiler emits declarations in the
# order of the source files, so the top-level declarations are sorted: moving a type to
# another file must not look like an API change. An attribute that the compiler prints
# on a line of its own, such as @available, stays with the declaration below it, and a
# compiler condition (#if ... #endif) stays one block with what it guards: moving either
# to another declaration is an API change. A declaration whose own access level is
# private, fileprivate, internal or package is not API: it is dropped with its attribute
# lines and its block, by indentation, as stated below. A build without library evolution
# prints such stored properties.
normalize() {
    # grep numbers every line in the C locale: in a UTF-8 locale it leaves out a line that holds a
    # byte that is no UTF-8 sequence, and the reader would never see that line. Exit 1 is a file
    # without lines; any other failure, such as a file it cannot read, stops the normalisation.
    # The single quotes hand the Python program to python3 unexpanded. skipcq: SH-2016
    { LC_ALL=C grep -n '^' "$1" || [ $? -eq 1 ]; } | python3 -c '
import re
import sys

def balance(text, opening, closing):
    # Counts the brackets of the arguments of an attribute, outside string literals.
    total, in_string, position = 0, False, 0
    while position < len(text):
        character = text[position]
        if in_string:
            if character == "\\":
                position += 1
            elif character == "\"":
                in_string = False
        elif character == "\"":
            in_string = True
        elif character == opening:
            total += 1
        elif character == closing:
            total -= 1
        position += 1
    return total

def skip_attributes(line):
    """The rest of the line after its leading attributes, arguments included."""
    position, end = 0, len(line)
    while True:
        while position < end and line[position].isspace():
            position += 1
        if position >= end or line[position] != "@":
            return line[position:]
        position += 1
        while position < end and (line[position].isalnum() or line[position] in "_."):
            position += 1
        if position < end and line[position] == "(":
            start = position
            while position < end:
                position += 1
                if balance(line[start:position], "(", ")") == 0:
                    break

def attributes_only(line):
    return skip_attributes(line).strip() == ""

HIDDEN = {"private", "fileprivate", "internal", "package"}

def hidden_declaration(line):
    for word in skip_attributes(line).split():
        if word in HIDDEN:
            return True
        if not word.isidentifier() or word in ("var", "let", "func", "init", "subscript", "case",
                                              "struct", "class", "enum", "protocol", "extension",
                                              "typealias", "actor", "associatedtype", "deinit"):
            return False
    return False

# Every line read must sit where the interface printer puts it, and a declaration that is not
# API is dropped by its indentation, never by counting its braces. The printer puts the members
# of a block two spaces deeper than the line that opens it and the closing brace at the
# indentation of that line; the body of an inlinable declaration it prints as written in the
# source, so a line of that body, its closing brace included, may sit at any indentation. A
# hidden declaration at indentation N goes with every following line indented deeper than N
# and, when its line ends with {, with the next line at indentation N that is exactly }. Any
# other line must be at the member level of the innermost open block, or be its closing brace;
# a compiler directive may sit anywhere. A line out of place stops the check with exit 2 and
# names its number, and so does a directive still open at the end.
#
# Each line from a hidden declaration to the end of its drop is checked for shape, and the
# shape is used only to refuse. The first line is a declaration; each line after it is a
# declaration, an accessor, a case, a line of attributes, a compiler directive or a lone { or }.
# A declaration has a declaration keyword after its attributes and modifiers, access levels
# among them, no = outside parentheses but the one of a typealias or an associatedtype, which
# names a type, and only plain single-line strings, numbers, nil, true, false or dotted members
# with balanced parentheses as default arguments. No checked line holds """, #, /* or */, the
# delimiters of text that spans lines. Any other line is a statement of a serialised body: the
# check stops with exit 2 and names its number. The shape decides nothing else: no brace is
# counted, and the drop still goes by indentation alone.
#
# Why this closes the family. A public member is lost only inside the drop of a hidden line
# that sits shallower, every line between them deeper than that line. Were the hidden line
# text of a multiline literal, the literal would close after it and before the member, which
# stands outside every body: on a line inside the drop, whose delimiter stops the check, or on
# a line no deeper than the hidden one, which ends the drop first. So the hidden line is code,
# and code of a body never passes as a hidden declaration: a local declaration takes no access
# level, the compiler nests no type in a body, a default argument or an initial value that the
# interface prints, and a statement, even one that starts with a variable named package, has no
# declaration keyword where a declaration has one. A hidden declaration of the printer drops
# nothing past its own block, because the printer puts the line after that block at its
# indentation or shallower. A crafted line that the shape accepts changes nothing, because
# nothing on it is counted.
DIRECTIVES = ("#if", "#elseif", "#else", "#endif")
DECLARATIONS = {"var", "let", "func", "init", "deinit", "subscript", "struct", "class", "enum",
                "protocol", "extension", "typealias", "associatedtype", "actor"}
ACCESS_LEVELS = {"open", "public", "package", "internal", "fileprivate", "private"}
MODIFIERS = {"static", "final", "override", "required", "convenience", "dynamic", "lazy",
             "optional", "mutating", "nonmutating", "indirect", "weak", "unowned", "nonisolated",
             "isolated", "consuming", "borrowing", "__consuming", "distributed", "prefix",
             "postfix", "infix"}
ACCESSORS = {"get", "set", "_read", "_modify", "unsafeAddress", "unsafeMutableAddress"}
SPANNING = ("\"\"\"", "/*", "*/", "#")
WORD = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
RAW_IDENTIFIER = re.compile(r"`[^`]*`")
OPERATOR_CHARACTERS = set("/=-+!*%<>&|^~?.")
NUMBER = re.compile(r"-?(0[xX][0-9A-Fa-f_]+|0[bB][01_]+|0[oO][0-7_]+|[0-9][0-9_]*(\.[0-9][0-9_]*)?([eE][+-]?[0-9]+)?)$")
PLAIN_STRING = re.compile(r"\"([^\"\\]|\\[^(])*\"$")
STRING = re.compile(r"\"([^\"\\]|\\.)*\"")
MEMBER = re.compile(r"\.?[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*(\(.*\))?$")

def indentation(line):
    return len(line) - len(line.lstrip())

def leading_keyword(line):
    """The first word after the attributes and the modifiers of a line, access levels included."""
    text = skip_attributes(line).lstrip()
    while True:
        word = WORD.match(text)
        if not word:
            return ""
        text = text[word.end():]
        if word.group() not in ACCESS_LEVELS and word.group() not in MODIFIERS:
            return word.group()
        if text.startswith("("):
            text = text[text.find(")") + 1:] if ")" in text else ""
        text = text.lstrip()

def assignments(text):
    """Each = that assigns a value, with the depth of the brackets around it."""
    found, depth, in_string, position = [], 0, False, 0
    while position < len(text):
        character = text[position]
        if in_string:
            if character == "\\":
                position += 1
            elif character == "\"":
                in_string = False
        elif text.startswith("//", position):
            break
        elif character == "\"":
            in_string = True
        elif character in "([":
            depth += 1
        elif character in ")]":
            depth -= 1
        elif character == "=":
            before = text[position - 1] if position > 0 else " "
            after = text[position + 1] if position + 1 < len(text) else " "
            if before not in OPERATOR_CHARACTERS and after not in OPERATOR_CHARACTERS:
                found.append((position, depth))
        position += 1
    return found

def default_value(text, start):
    """The default argument that starts at `start`: up to the next comma or closing bracket."""
    depth, in_string, position = 0, False, start
    while position < len(text):
        character = text[position]
        if in_string:
            if character == "\\":
                position += 1
            elif character == "\"":
                in_string = False
        elif character == "\"":
            in_string = True
        elif character in "([":
            depth += 1
        elif character in ")]":
            if depth == 0:
                break
            depth -= 1
        elif character == "," and depth == 0:
            break
        position += 1
    return text[start:position].strip()

def modelled_default(value):
    if value in ("nil", "true", "false") or NUMBER.match(value) or PLAIN_STRING.match(value):
        return True
    outside = STRING.sub("\"\"", value)
    if not MEMBER.match(outside) or "\\(" in value:
        return False
    if any(character in outside for character in "`/#{}\\"):
        return False
    return balance(outside, "(", ")") == 0

def readable_in_a_hidden_block(line):
    text = line.strip()
    directive = text.startswith(DIRECTIVES)
    if any(delimiter in (text[1:] if directive else text) for delimiter in SPANNING):
        return False
    if directive or text in ("{", "}") or attributes_only(line):
        return True
    keyword = leading_keyword(line)
    if keyword in ACCESSORS or keyword == "case":
        return True
    if keyword not in DECLARATIONS:
        return False
    # A raw identifier may hold a bracket or an =, and it never holds a backquote.
    code = RAW_IDENTIFIER.sub("x", skip_attributes(line))
    for position, depth in assignments(code):
        if depth > 0:
            if not modelled_default(default_value(code, position + 1)):
                return False
        elif keyword not in ("typealias", "associatedtype"):
            return False
    return True

def refuse(number, line):
    sys.exit("check-api: line " + str(number) + " is a statement of a serialised body: " + line.strip())

def public_lines(lines):
    kept, held, blocks, conditions, position = [], [], [], 0, 0
    while position < len(lines):
        number, line = lines[position]
        position += 1
        directive = line.lstrip()
        if directive.startswith(DIRECTIVES):
            if directive.startswith("#if"):
                conditions += 1
            elif directive.startswith("#endif"):
                conditions -= 1
            kept.extend(held)
            held = []
            kept.append(line)
            continue
        level = indentation(line)
        if blocks and level == blocks[-1] and line.strip() == "}":
            blocks.pop()
            kept.extend(held)
            held = []
            kept.append(line)
            continue
        if level != (blocks[-1] + 2 if blocks else 0):
            sys.exit("check-api: line " + str(number) + " is not where the interface printer puts it: " + line.strip())
        if line.strip() and attributes_only(line):
            held.append(line)
            continue
        if hidden_declaration(line):
            if leading_keyword(line) not in DECLARATIONS or not readable_in_a_hidden_block(line):
                refuse(number, line)
            held = []
            while position < len(lines) and indentation(lines[position][1]) > level:
                if not readable_in_a_hidden_block(lines[position][1]):
                    refuse(*lines[position])
                position += 1
            if (line.rstrip().endswith("{") and position < len(lines)
                    and indentation(lines[position][1]) == level and lines[position][1].strip() == "}"):
                position += 1
            continue
        kept.extend(held)
        held = []
        kept.append(line)
        if line.rstrip().endswith("{"):
            blocks.append(level)
    if conditions != 0:
        sys.exit("check-api: a compiler directive is still open at the end of the interface")
    return kept + held

# grep numbers every line of the interface, and the text is cut at the line feed alone, so that
# each piece but the empty one after the last line feed is one numbered line. str.splitlines
# would cut at more characters, among them the line breaks below, which grep leaves inside a
# line: text after one of them, in a string of a body, would read as a line of its own under a
# number the text wrote itself. The check refuses each of them on any line, comments and imports
# included, and it never uses str.splitlines. The interface is read as bytes and decoded as
# UTF-8, and written as UTF-8, whatever the locale says: a locale that took its bytes for other
# characters would let a line separator pass.
LINE_BREAK = re.compile("[\r\x0b\x0c\x85\N{LINE SEPARATOR}\N{PARAGRAPH SEPARATOR}]")
try:
    text = sys.stdin.buffer.read().decode("utf-8")
except UnicodeDecodeError as error:
    sys.exit("check-api: the interface is not valid UTF-8: " + str(error))
sys.stdout.reconfigure(encoding="utf-8")

numbered = []
records = text.split("\n")
if records.pop() != "":
    sys.exit("check-api: the numbered text is not ended by a line feed")
for record in records:
    number, colon, line = record.partition(":")
    if not colon or not (number.isascii() and number.isdigit()):
        sys.exit("check-api: not a line numbered by grep: " + record[:60])
    found = LINE_BREAK.search(line)
    if found:
        sys.exit("check-api: line " + number + " holds a line break other than a line feed: U+"
                 + format(ord(found.group()), "04X"))
    if line and not line.startswith(("//", "import ")):
        numbered.append((int(number), line))

blocks, current, conditions = [], [], 0
for line in public_lines(numbered):
    starts_declaration = bool(line) and not line[0].isspace() and line != "}"
    if starts_declaration and current and conditions == 0 and not all(attributes_only(held) for held in current):
        blocks.append("\n".join(current))
        current = []
    current.append(line)
    directive = line.lstrip()
    if directive.startswith("#if"):
        conditions += 1
    elif directive.startswith("#endif"):
        conditions -= 1
if current:
    blocks.append("\n".join(current))
print("\n".join(sorted(blocks)))
'
}

# Each case holds two interface texts and says whether they must normalise to the same
# text. A change to normalize() that hides an API change, or reports one that is not
# there, fails one of them.
if [ "${1:-}" = "--self-test" ]; then
    CASES="$ROOT/Fixtures/API/normalizer"
    FAILED=0
    for CASE in "$CASES"/*.txt; do
        NAME="$(basename "$CASE" .txt)"
        if ! grep -qx -- '--- A ---' "$CASE" || ! grep -qx -- '--- B ---' "$CASE"; then
            echo "check-api: FAIL $NAME: the case needs a line '--- A ---' and a line '--- B ---'" >&2
            FAILED=1
            continue
        fi
        EXPECTED="$(sed -n 's/^# expect: //p' "$CASE")"
        # awk reads the cases as bytes, so that no locale stops it on a character of a case.
        LC_ALL=C awk '/^--- A ---$/ { part = "A"; next } /^--- B ---$/ { part = "B"; next } part == "A"' "$CASE" > "$WORK/case-a.txt"
        LC_ALL=C awk '/^--- B ---$/ { part = "B"; next } part == "B"' "$CASE" > "$WORK/case-b.txt"
        # A case that expects an error passes when the normalisation of its text A fails with
        # the message the case names: a crash, or another error, must not stand in for it.
        if [ "$EXPECTED" = "error" ]; then
            MESSAGE="$(sed -n 's/^# message: //p' "$CASE")"
            if [ -z "$MESSAGE" ]; then
                echo "check-api: FAIL $NAME: an error case needs a line '# message: <text of the error>'" >&2
                FAILED=1
            elif normalize "$WORK/case-a.txt" > /dev/null 2> "$WORK/case-a.error"; then
                echo "check-api: FAIL $NAME: expected an error, the normalisation of A succeeded" >&2
                FAILED=1
            elif ! grep -qF -- "$MESSAGE" "$WORK/case-a.error"; then
                echo "check-api: FAIL $NAME: expected the error '$MESSAGE', the normalisation said: $(head -c 300 "$WORK/case-a.error")" >&2
                FAILED=1
            else
                echo "check-api: ok   $NAME"
            fi
            continue
        fi
        if ! normalize "$WORK/case-a.txt" > "$WORK/case-a.normalized" || ! normalize "$WORK/case-b.txt" > "$WORK/case-b.normalized"; then
            echo "check-api: FAIL $NAME: the normalisation stopped with an error" >&2
            FAILED=1
            continue
        fi
        if cmp -s "$WORK/case-a.normalized" "$WORK/case-b.normalized"; then ACTUAL="same"; else ACTUAL="different"; fi
        if [ "$ACTUAL" = "$EXPECTED" ]; then
            echo "check-api: ok   $NAME"
        else
            echo "check-api: FAIL $NAME: expected $EXPECTED, the normalised texts are $ACTUAL" >&2
            FAILED=1
        fi
    done
    # A file that cannot be read is an error, not an interface without declarations.
    if normalize "$WORK/no-such-interface.txt" > /dev/null 2>&1; then
        echo "check-api: FAIL unreadable-input: the normalisation of a missing file succeeded" >&2
        FAILED=1
    else
        echo "check-api: ok   unreadable-input"
    fi
    # A file the check cannot read exactly stops the normalisation with a message of its own,
    # whatever the locale of the caller. grep prints a notice in place of the lines of a file with
    # a NUL byte, and the notice holds no line number; the path of the second file holds a colon,
    # so its notice has a part before the colon that is no number either.
    expect_refused() {
        if (export LC_ALL="${4:-C}"; normalize "$1") > /dev/null 2> "$WORK/$2.error"; then
            echo "check-api: FAIL $2: the normalisation succeeded" >&2
            FAILED=1
        elif ! grep -qF -- "$3" "$WORK/$2.error"; then
            echo "check-api: FAIL $2: expected '$3', the normalisation said: $(head -c 300 "$WORK/$2.error")" >&2
            FAILED=1
        else
            echo "check-api: ok   $2"
        fi
    }
    printf 'public struct First {\n  public func keep()\n}\n\000' > "$WORK/binary-input.txt"
    expect_refused "$WORK/binary-input.txt" binary-input "not a line numbered by grep"
    mkdir -p "$WORK/colon:dir"
    printf 'public struct First {\n  public func keep()\n}\n\000' > "$WORK/colon:dir/binary-input.txt"
    expect_refused "$WORK/colon:dir/binary-input.txt" binary-input-with-a-colon "not a line numbered by grep"
    # The byte 0377 starts no UTF-8 sequence, whatever the locale of the caller.
    printf 'public struct First {\n  public func keep(s: Swift.String = "\377")\n}\n' > "$WORK/invalid-utf8.txt"
    expect_refused "$WORK/invalid-utf8.txt" invalid-utf8 "the interface is not valid UTF-8"
    # In a UTF-8 locale grep leaves out a line that starts with a byte that is no UTF-8 sequence, so
    # the normalisation must number the lines in the C locale to see that line at all.
    printf 'public struct First {\n\377  public func keep()\n}\n' > "$WORK/invalid-utf8-first.txt"
    expect_refused "$WORK/invalid-utf8-first.txt" invalid-utf8-at-a-line-start "the interface is not valid UTF-8" en_US.UTF-8
    # The text is written as UTF-8 whatever the output stream encodes. PYTHONIOENCODING sets that
    # stream, and no locale changes it: a character that Latin-1 cannot hold comes out as the same
    # UTF-8 bytes in both runs.
    printf 'public struct Price {\n  public func show(symbol: Swift.String = "\342\202\254")\n}\n' > "$WORK/euro-sign.txt"
    if normalize "$WORK/euro-sign.txt" > "$WORK/euro-sign.expected" && (export PYTHONIOENCODING=latin-1; normalize "$WORK/euro-sign.txt") > "$WORK/euro-sign.latin1" 2> "$WORK/euro-sign.error" && cmp -s "$WORK/euro-sign.expected" "$WORK/euro-sign.latin1"; then
        echo "check-api: ok   output-encoding"
    else
        echo "check-api: FAIL output-encoding: the Latin-1 stream differs or stopped: $(head -c 300 "$WORK/euro-sign.error")" >&2
        FAILED=1
    fi
    exit "$FAILED"
fi

# The files of a module are passed in one fixed order. A plain sort follows the locale
# of the machine, and the order of the files is the order in which the compiler emits
# the declarations.
swift_sources() {
    find "$ROOT/$1" -name '*.swift' | LC_ALL=C sort
}

# The compiler is called for the iOS simulator, a platform the packages are released
# for. It is called directly, because a module that shares its name with one of its
# types cannot pass the interface verifier that a build through xcodebuild always runs.
# Exit 1 says that the interface differs. An SDK that cannot be located is not that.
if ! SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)" || [ ! -d "$SDK_PATH" ]; then
    echo "check-api: the iOS simulator SDK cannot be located." >&2
    exit 2
fi
TARGET="arm64-apple-ios17.0-simulator"

# Bash 3.2, the version macOS ships, treats an empty array as unbound under set -u, hence
# the ${name[@]+"${name[@]}"} form for arrays that may be empty.
if [ "${#PREPARE[@]}" -gt 0 ]; then
    if ! (cd "$ROOT" && "${PREPARE[@]}") > "$WORK/prepare.log" 2>&1; then
        echo "check-api: the preparation (${PREPARE[*]}) failed. See ${WORK#"$ROOT"/}/prepare.log" >&2
        tail -5 "$WORK/prepare.log" >&2
        exit 2
    fi
fi

for DEPENDENCY in ${DEPENDENCIES[@]+"${DEPENDENCIES[@]}"}; do
    DEPENDENCY_MODULE="${DEPENDENCY%%|*}"
    REST="${DEPENDENCY#*|}"
    DEPENDENCY_DIR="${REST%%|*}"
    read -r -a DEPENDENCY_FLAGS <<< "${REST#*|}"
    DEPENDENCY_SOURCES=()
    while IFS= read -r file; do
        DEPENDENCY_SOURCES+=("$file")
    done < <(swift_sources "$DEPENDENCY_DIR")
    if [ "${#DEPENDENCY_SOURCES[@]}" -eq 0 ]; then
        echo "check-api: no Swift source in $DEPENDENCY_DIR for the dependency $DEPENDENCY_MODULE." >&2
        exit 2
    fi
    if ! xcrun --sdk iphonesimulator swiftc \
        -target "$TARGET" -sdk "$SDK_PATH" -I "$WORK" \
        -module-name "$DEPENDENCY_MODULE" \
        ${DEPENDENCY_FLAGS[@]+"${DEPENDENCY_FLAGS[@]}"} \
        -emit-module -emit-module-path "$WORK/$DEPENDENCY_MODULE.swiftmodule" \
        "${DEPENDENCY_SOURCES[@]}" \
        > "$WORK/swiftc-$DEPENDENCY_MODULE.log" 2>&1; then
        echo "check-api: the dependency $DEPENDENCY_MODULE does not compile. See ${WORK#"$ROOT"/}/swiftc-$DEPENDENCY_MODULE.log" >&2
        grep -E "error:" "$WORK/swiftc-$DEPENDENCY_MODULE.log" | sort -u | head -20 >&2 || true
        exit 2
    fi
done

SOURCES=()
while IFS= read -r file; do
    SOURCES+=("$file")
done < <(swift_sources "$SOURCE_DIR")
if [ "${#SOURCES[@]}" -eq 0 ]; then
    echo "check-api: no Swift source in $SOURCE_DIR. Check SOURCE_DIR in the settings." >&2
    exit 2
fi

EVOLUTION_FLAGS=()
if [ "$LIBRARY_EVOLUTION" = "yes" ]; then
    EVOLUTION_FLAGS=(-enable-library-evolution)
fi

# The interface of an earlier run must not stand in for this one.
rm -f "$INTERFACE"
if ! xcrun --sdk iphonesimulator swiftc \
    -target "$TARGET" -sdk "$SDK_PATH" -I "$WORK" \
    -module-name "$MODULE" \
    -package-name "$MODULE" \
    ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} \
    ${EVOLUTION_FLAGS[@]+"${EVOLUTION_FLAGS[@]}"} \
    -emit-module -emit-module-path "$WORK/$MODULE.swiftmodule" \
    -emit-module-interface-path "$INTERFACE" \
    -no-verify-emitted-module-interface \
    "${SOURCES[@]}" \
    > "$WORK/swiftc.log" 2>&1; then
    echo "check-api: the library does not compile. See ${WORK#"$ROOT"/}/swiftc.log" >&2
    grep -E "error:" "$WORK/swiftc.log" | sort -u | head -20 >&2 || true
    exit 2
fi

if ! normalize "$INTERFACE" > "$CURRENT"; then
    echo "check-api: the interface ${INTERFACE#"$ROOT"/} could not be normalised." >&2
    exit 2
fi

# Every package here has public API: an interface without a declaration means the check went
# wrong, so it is neither saved nor compared.
if ! grep -q '[^[:space:]]' "$CURRENT"; then
    echo "check-api: the public interface is empty: the check could not read it." >&2
    exit 2
fi

if [ "${1:-}" = "--update" ]; then
    mkdir -p "$(dirname "$BASELINE")"
    cp "$CURRENT" "$BASELINE"
    echo "check-api: baseline updated: ${BASELINE#"$ROOT"/}"
    exit 0
fi

if [ ! -f "$BASELINE" ]; then
    echo "check-api: no baseline at ${BASELINE#"$ROOT"/}. Run with --update." >&2
    exit 2
fi

# The baseline goes through the same normalization, so the comparison does not depend on
# the order of the declarations in either file.
if ! normalize "$BASELINE" > "$WORK/baseline.txt"; then
    echo "check-api: the baseline ${BASELINE#"$ROOT"/} could not be normalised." >&2
    exit 2
fi

if diff -u --label "$(basename "$BASELINE")" --label "current interface" "$WORK/baseline.txt" "$CURRENT" > "$WORK/api.diff"; then
    echo "check-api: the public interface matches the baseline."
    exit 0
fi

echo "check-api: the public interface differs from the baseline." >&2
echo "  '-' lines were removed or changed: that breaks the public contract." >&2
echo "  '+' lines are new public API: run Scripts/check-api.sh --update and commit the baseline." >&2
cat "$WORK/api.diff" >&2
exit 1
