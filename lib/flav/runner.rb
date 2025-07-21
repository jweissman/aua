require "debug"
require "yaml"
require "rainbow/refinement"

# Flav - Aura-native task runner
# Reads Flavfile (YAML) and executes tasks with dependency resolution
module Flav
  # TODO: Would be nice to have a Task class
  # Task = Data.define(:name, :wants, :description, :filters, :repeat, :if, :unless) do
  # end

  class Runner
    using Rainbow

    def initialize(flavfile_path = "Flavfile")
      @flavfile_path = flavfile_path
      @tasks = {}
      @executed = {}
      @pipeline_data = {} # Store data passed between pipeline stages
      @default_path = "app:generates" # Default namespace for tasks
      load_flavfile
    end


    def load_flavfile
      unless File.exist?(@flavfile_path)
        puts "No #{@flavfile_path} found in current directory.".color(:red)
        exit 1
      end

      begin
        content = YAML.load_file(@flavfile_path)
        leaves = flatten_tree(content)
        @tasks = leaves.to_h do |materialized_path, item|
          task_name = item["task"]
          wants = item["wants"] ? item["wants"].split(/,\s*/) : []
          path = materialized_path.split(":")
          namespace = path[0..-2].join("/")
          material_path_up_to = path[0..-2].join(":")
          [materialized_path, {
            "task" => "#{namespace}/#{task_name}.aura",
            "materialized_path" => material_path_up_to,
            "description" => "Generate #{task_name}",
            "wants" => wants,
            "if" => item["if"],
            "unless" => item["unless"],
            # "prefilter" => item["prefilter"] || [],
            # "postfilter" => item["postfilter"] || [],
            "repeat" => item["repeat"] || 1,
            "pipeline" => true
          }]
        end


        puts "Loaded #{@tasks.keys.length} tasks from #{@flavfile_path}".color(:green)
      rescue StandardError => e
        puts "Error loading #{@flavfile_path}: #{e.message}".color(:red)
        puts e.backtrace.join("\n").color(:red)
        exit 1
      end
    end

    def list_tasks
      puts "Available tasks:".color(:cyan).bright
      @tasks.each do |name, config|
        desc = config["description"] || "No description"
        wants = config["wants"] || []
        wants_str = wants.empty? ? "" : " [wants: #{wants.join(", ")}]"
        # pipeline_str = config["pipeline"] ? " 🔗".color(:green) : ""
        repeated_str = config["repeat"] ? " (repeated #{config["repeat"]} times)" : ""
        puts "  #{name.color(:yellow).ljust(48)} - #{desc}#{wants_str.color(:blue)}#{repeated_str}"
      end
    end

    def repeat_task(name, opts={}, current_path: @default_path, repeat_count: 1)
      puts "Repeating task '#{name}' #{repeat_count} times".color(:green)
      results = []
      repeat_count.times do |i|
        puts "  Run #{i + 1}/#{repeat_count}".color(:blue)
        results << run_task(name, opts.except("n"), current_path:, nonce: i.to_s)
      end
      puts "Completed repeating task '#{name}' #{repeat_count} times".color(:green)
      results
    end

    def run_task(name, opts={}, current_path: @default_path, nonce: nil)
      times = (opts.delete("n") || opts.delete("repeat") || opts.delete("times") || opts.delete("count") || 1).to_i
      return repeat_task(name, opts, current_path:, repeat_count: times) if times > 1

      pathed_name = current_path ? "#{current_path}:#{name}" : name
      name = if @tasks.key?(name)
                   name
                 elsif @tasks.key?(pathed_name)
                   pathed_name
                 else
                   puts "Task '#{name}' not found in current path '#{current_path}'".color(:red)
                   list_tasks
                   exit 1
                 end

      # Create cache key that includes nonce for proper isolation
      cache_key = nonce ? "#{name}:#{nonce}" : name
      
      # Check if already executed (avoid cycles)
      if @executed[cache_key]
        puts "Task '#{name}' already executed.".color(:blue)
        return @pipeline_data[cache_key] # Return cached pipeline data
      end

      task_config = @tasks[name]

      # Execute dependencies first and collect their pipeline data
      wants = task_config["wants"] || []
      dependency_data = {}

      wants.each do |dep|
        if dep.include?(":")
          # Handle task:alias syntax (e.g., creature:a, creature:b) or task:count syntax (e.g., creature:300)
          task_name, suffix = dep.split(":", 2)
          
          # Check if suffix is numeric (repetition count) or alias
          if suffix.match?(/^\d+$/)
            # Numeric suffix - handle as repetition
            count = suffix.to_i
            puts "Running dependency: #{task_name} (#{count} times)".color(:blue)
            combined_nonce = nonce ? "#{nonce}:#{task_name}" : task_name
            results = []
            count.times do |i|
              dep_result = run_task(task_name, current_path: task_config["materialized_path"], nonce: "#{combined_nonce}:#{i}")
              results << dep_result if dep_result
            end
            dependency_data[task_name] = results
          else
            # Alias suffix - handle as aliased dependency
            alias_name = suffix
            puts "Running dependency: #{task_name} (as #{alias_name})".color(:blue)
            # Combine parent nonce with alias to ensure uniqueness across iterations
            combined_nonce = nonce ? "#{nonce}:#{alias_name}" : alias_name
            dep_result = run_task(task_name, current_path: task_config["materialized_path"], nonce: combined_nonce)
            dependency_data[alias_name] = dep_result if dep_result
          end
        else
          # Regular dependency - propagate nonce to ensure full isolation
          puts "Running dependency: #{dep}".color(:blue)
          dep_result = run_task(dep, current_path: task_config["materialized_path"], nonce: nonce)
          dependency_data[dep] = dep_result if dep_result
        end
      end

      # Check conditions
      if task_config["if"]
        condition_result = evaluate_condition(task_config["if"])
        unless condition_result
          puts "Skipping task '#{name}' - condition not met: #{task_config["if"]}".color(:yellow)
          @executed[cache_key] = true
          return
        end
      end

      if task_config["unless"]
        condition_result = evaluate_condition(task_config["unless"])
        if condition_result
          puts "Skipping task '#{name}' - unless condition met: #{task_config["unless"]}".color(:yellow)
          @executed[cache_key] = true
          return
        end
      end

      # Execute the task
      puts "Running task: #{name}".color(:green).bright
      result = execute_task(name, task_config, dependency_data)
      @executed[cache_key] = true

      # Store result for pipeline tasks
      if task_config["pipeline"] && result
        @pipeline_data[cache_key] = result
        puts "  └─ Pipeline data: #{result.inspect}".color(:cyan)
      end

      # result["nonce"] = nonce.to_s if nonce
      if result.is_a?(Hash)
        result["nonce"] = nonce.to_s if nonce
      end
      result
    end

    private

    def flatten_tree(tree, prefix = "", item_key = 'task')
      flat_leaves = {}
      tree.each do |key, value|
        if value.is_a?(Hash)
          # Recursive case: flatten nested hashes
          nested_leaves = flatten_tree(value, "#{prefix}#{key}:")
          flat_leaves.merge!(nested_leaves)
        elsif value.is_a?(Array)
          # Handle array of tasks
          value.each do |item|
            if item.is_a?(Hash)
              # Each item is a task definition
              item_name = "#{prefix}#{key}:#{item[item_key]}"
              flat_leaves[item_name] = item
            else
              puts "Invalid task format in Flavfile: #{item.inspect}".color(:red)
            end
          end
        end
      end

      if prefix.empty?
        puts "Flattened tasks: #{flat_leaves.keys.join(", ").color(:cyan)}"
      end

      return flat_leaves
    end

    def evaluate_condition(condition)
      # Simple evaluation - for now just check file existence
      # Later we can execute this as Aura code
      if condition.start_with?("file_exists:")
        file_path = condition.sub("file_exists:", "").strip
        File.exist?(file_path)
      elsif condition.start_with?("!")
        # Negation
        !evaluate_condition(condition[1..-1])
      else
        # For now, try to evaluate as Aura code
        begin
          result = Aua.run(condition)
          case result
          when Aua::Bool then result.value
          when Aua::Nihil then false
          else true
          end
        rescue StandardError
          false
        end
      end
    end

    def execute_task(name, config, dependency_data = {})
      start_time = Time.now

      if config["task"]
        # Execute Aura script
        script_path = config["task"]
        if File.exist?(script_path)
          puts "  └─ Executing Aura script: #{script_path}".color(:blue)

          # For pipeline tasks, we need to execute the script and capture output
          if config["pipeline"]
            result = execute_aura_pipeline_script(script_path, dependency_data)
          else
            # result = system("aura #{script_path}")
            # result = system("/home/jweissman/work/games/aua/bin/aura #{script_path}")
            unless result
              puts "Task '#{name}' failed with exit code #{$?.exitstatus}".color(:red)
              exit 1
            end
            result = nil # Non-pipeline tasks don't return data
          end
        else
          puts "Script not found: #{script_path}".color(:red)
          exit 1
        end
      elsif config["command"]
        # Execute shell command
        command = config["command"]
        puts "  └─ Executing command: #{command}".color(:blue)
        result = system(command)
        unless result
          puts "Task '#{name}' failed with exit code #{$?.exitstatus}".color(:red)
          exit 1
        end
        result = nil # Shell commands don't return pipeline data
      elsif config["script"]
        # Inline Aura script
        puts "  └─ Executing inline Aura script".color(:blue)
        begin
          aura_result = Aua.run(config["script"])
          puts "  └─ Result: #{aura_result.pretty}".color(:green)

          # If this is a pipeline task, extract the value
          result = if config["pipeline"]
                     case aura_result
                     when Aua::Str then aura_result.value
                     when Aua::Int then aura_result.value
                     when Aua::Bool then aura_result.value
                     else aura_result.pretty
                     end
                   end
        rescue StandardError => e
          puts "Inline script failed: #{e.message}".color(:red)
          exit 1
        end
      else
        puts "Task '#{name}' has no executable content (task, command, or script)".color(:yellow)
        result = nil
      end

      duration = ((Time.now - start_time) * 1000).round(2)
      puts "  └─ Completed in #{duration}ms".color(:green)

      result
    end

    def execute_aura_pipeline_script(script_path, dependency_data)
      # Execute the script directly in the Aura VM with dependency data

      # Read the script content
      script_content = File.read(script_path)

      # Create a new VM instance with dependency data in environment
      vm = Aua.vm # Aua::Runtime::VM.new
      # interpreter

      # Add dependency data to environment as params hash
      unless dependency_data.empty?
        # Convert dependency data to Aura objects
        aura_params = {}
        dependency_data.each do |key, value|
          aura_params[key] = case value
                             when String then Aua::Str.new(value)
                             when Integer then Aua::Int.new(value)
                             when Float then Aua::Float.new(value)
                             when TrueClass, FalseClass then Aua::Bool.new(value)
                             else Aua::Str.new(value.to_s)
                             end
        end

        # Set params in VM environment
        vm.env["params"] = Aua::Dict.new(aura_params)
      end

      # Execute the script
      result = Aua.run(script_content)

      # Extract the result value for pipeline use
      case result
      when Aua::Str
        result.value
      when Aua::Int
        result.value.to_s
      when Aua::Bool
        result.value.to_s
      when Aua::Nihil
        nil
      else
        result.pretty
      end
    rescue StandardError => e
      puts "Pipeline script failed: #{e.message}".color(:red)
      puts e.backtrace.join("\n").color(:red)
      exit 1
    end
  end
end
