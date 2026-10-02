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

# Define a helper to check if the dependency manager is 'POD'
def is_pod_configuration(manager)
  manager == DEPENDENCY_MANAGER_POD
end
