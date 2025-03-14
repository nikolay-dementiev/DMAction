# Define constants for dependency manager settings
PROJECT_NAME = 'DMActionTestProject'
DEPENDENCY_MANAGER_POD = 'POD'
DEPENDENCY_MANAGER_SPM = 'SPM'
DEPENDENCY_MANAGER_KEY = 'DEPENDENCY_MANAGER'
DEPENDENCY_MANAGER_FILE = '.dependency_manager'
VALID_DEPENDENCY_MANAGERS = [DEPENDENCY_MANAGER_POD, DEPENDENCY_MANAGER_SPM]
LOG_INFO = 'Info'
LOG_ERROR = 'Error'

# Helper function to validate the dependency manager value
def valid_dependency_manager?(value)
  VALID_DEPENDENCY_MANAGERS.include?(value)
end

# Main function to determine the dependency manager
def dependency_manager
  # Helper function to read the dependency manager from the environment variable
  def read_from_env
    env_value = ENV[DEPENDENCY_MANAGER_KEY]
    if env_value
      if valid_dependency_manager?(env_value)
        return env_value
      else
        puts "#{LOG_ERROR}: Invalid #{DEPENDENCY_MANAGER_KEY} value '#{env_value}' provided in the environment. Ignoring it"
      end
    end
    nil
  end

  # Helper function to read the dependency manager from the file
  def read_from_file
    return nil unless File.exist?(DEPENDENCY_MANAGER_FILE)

    File.readlines(DEPENDENCY_MANAGER_FILE).each do |line|
      if line.start_with?("#{DEPENDENCY_MANAGER_KEY}=")
        file_value = line.strip.split('=').last
        if valid_dependency_manager?(file_value)
          puts "#{LOG_INFO}: #{DEPENDENCY_MANAGER_KEY} value '#{file_value}' was picked up from the file '#{DEPENDENCY_MANAGER_FILE}'"
          return file_value
        else
          puts "#{LOG_ERROR}: Invalid #{DEPENDENCY_MANAGER_KEY} value '#{file_value}' found in the file '#{DEPENDENCY_MANAGER_FILE}'. Ignoring it"
        end
      end
    end
    nil
  end
  
  # Try reading from the environment variable
  env_value = read_from_env
  return env_value if env_value

  # Try reading from the file
  file_value = read_from_file
  return file_value if file_value

  # If no valid value is found, print an error message and default to "POD"
  puts "#{LOG_ERROR}: Invalid or missing #{DEPENDENCY_MANAGER_KEY} value. Defaulting to '#{DEPENDENCY_MANAGER_POD}'"
  DEPENDENCY_MANAGER_POD
end

# Save the current dependency manager to a file (optional)
def save_dependency_manager(manager)
  File.write(DEPENDENCY_MANAGER_FILE, "#{DEPENDENCY_MANAGER_KEY}=#{manager}")
  puts "#{LOG_INFO}: Manager '#{manager}' was successfully saved in the file '#{DEPENDENCY_MANAGER_FILE}'"
rescue StandardError => e
  puts "#{LOG_ERROR}: Failed to save dependency manager: #{e.message}"
end

# Define a helper method to execute shell commands with optional info and error messages
def command(cmd, info_text: nil, error_text: nil)
  # Execute the command and capture both stdout and stderr
  output = `#{cmd} 2>&1`
  exit_status = $?.exitstatus
  
  # Check if the command succeeded or failed
  if exit_status == 0
    puts "#{LOG_INFO}: #{info_text}" if info_text # Print the info message if provided and command succeeded
  else
    puts "#{LOG_ERROR}: #{error_text}. Exit status: #{exit_status}. Output: #{output}" if error_text # Print the error message if provided and command failed
  end

  exit_status # Return the exit status for further handling if needed
end

# Clean the Xcode project before installing pods
def clean_xcode_project(project_name)
  puts "#{LOG_INFO}: Cleaning Xcode project..."
  
  # Helper method to extract and filter schemes
  def extract_schemes(schemes_output)
    schemes = []
    capturing = false

    schemes_output.lines.each do |line|
      # Start capturing when we encounter the "Schemes:" line
      if line.strip.start_with?("Schemes:")
        capturing = true
        next
      end

      # Stop capturing when we encounter a blank line or reach the end
      if capturing && line.strip.empty?
        break
      end

      # Capture non-empty lines as scheme names
      if capturing && !line.strip.empty?
        scheme_name = line.strip

        # Filter out unwanted schemes (e.g., Pods-related schemes)
        unless scheme_name.include?("Pods-") || scheme_name.match?(/\(.*\)/) || scheme_name.empty?
          schemes << scheme_name
        end
      end
    end

    schemes
  end
  
  def pluralize(count, singular, plural)
    count == 1 ? singular : plural
  end

  begin
    # List all schemes in the workspace
    schemes_output = `xcodebuild -workspace #{project_name}.xcworkspace -list 2>/dev/null`
    if $?.success?
      schemes = extract_schemes(schemes_output)
      
      verb = pluralize(schemes.size, "was", "were")
      puts "#{LOG_INFO}: #{schemes.size} scheme#{'s' if schemes.size != 1} #{verb} found: #{schemes.join(', ')}"
      
      schemes.each do |scheme|
        puts "#{LOG_INFO}: Cleaning workspace for scheme: #{scheme}"
        command(
                "xcodebuild clean -workspace #{project_name}.xcworkspace -scheme #{scheme} >/dev/null",
                error_text: "Failed to clean xcodebuild workspace '#{project_name}' with scheme '#{scheme}'"
                )
      end
    else
      puts "#{LOG_ERROR}: Failed to list schemes. Skipping cleaning"
    end

    # Remove DerivedData
    derived_data_path = File.expand_path('~/Library/Developer/Xcode/DerivedData')
    if Dir.exist?(derived_data_path)
      puts "#{LOG_INFO}: Removing DerivedData..."
      exit_status_derived_data_path_removing = command(
                                                       "rm -rf #{derived_data_path}",
                                                       error_text: "Failed to remove '#{derived_data_path}'"
                                                       )
      if exit_status_derived_data_path_removing != 0
        puts "#{LOG_INFO}: ! Try to close the Xcode project and retry once again !"
      end
    else
      puts "#{LOG_INFO}: DerivedData directory not found"
    end

    puts "#{LOG_INFO}: Cleanup complete!"
  rescue StandardError => e
    puts "#{LOG_ERROR}: Error during cleanup: #{e.message}"
  end
end

# Define a helper to check if the dependency manager is 'POD'
def is_pod_configuration(manager)
  manager == DEPENDENCY_MANAGER_POD
end
