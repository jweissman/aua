module Aua
  module Runtime
    class VM
      module Builtin
        class << self
          def builtin_size(obj)
            raise Error, "size requires a single argument" unless obj.is_a?(Obj)

            case obj
            when Aua::List then Int.new(obj.values.length)
            when Aua::Dict then Int.new(obj.values.length)
            when Aua::Str then Int.new(obj.value.length)
            when Aua::RecordObject then Int.new(obj.keys.length)
            else
              raise Error, "size not supported for type: #{obj.class.name}"
            end
          end

          def builtin_write_file(file_path, content)
            raise Error, "write_file requires two arguments" unless file_path.is_a?(Str)
            raise Error, "write_file requires a second argument" unless content.is_a?(Str)

            path = file_path.value
            Aua.logger.info "Writing to file: #{path}"
            begin
              File.open(path, "w") do |file|
                file.write(content.value)
              end
              Aua.logger.info "Successfully wrote to file: #{path}"
              Aua::Nihil.new
            rescue => e
              Aua.logger.error "Failed to write to file: #{e.message}"
              raise Error, "Failed to write to file: #{e.message}"
            end
          end

          def builtin_cast(obj, target)
            raise Error, "cast requires two arguments" unless obj.is_a?(Obj)

            # GenericType extends Klass, so we can treat it as a Klass
            raise Error, "Cannot cast to non-Klass: \\#{target.inspect}" unless target.is_a?(Klass)

            klass = target
            # Generic casting using LLM + JSON schema
            Aua.logger.info("builtin_cast") do
              "Casting object: \\#{obj.inspect} to class: \\#{klass.inspect} " \
                "(\\#{klass.name} annotated as '#{klass.type_annotation}')"
            end
            chat = Aua::LLM.chat
            ret = chat.with_json_guidance(schema_for(klass)) do
              chat.ask(build_cast_prompt(obj, klass))
            end
            Aua.logger.info "Response from LLM: \\#{ret.inspect}"
            value = JSON.parse(ret)["value"]
            result = klass.construct(value)
            Aua.logger.info "Cast result: \\#{result.inspect} (\\#{result.class})"

            # Set the type annotation for both generic types and record types
            if klass.is_a?(Aua::Runtime::GenericType) || klass.is_a?(Aua::Runtime::RecordType)
              type_annotation = klass.name
              Aua.logger.info "Setting type annotation: #{type_annotation}"
              result.instance_variable_set(:@type_annotation, type_annotation)
            end

            Aua.logger.info "Cast target was \\#{klass.name} (result type annotation: \\#{begin
              result.instance_variable_get(:@type_annotation)
            rescue StandardError
              "none"
            end})"
            result
          end

          def schema_for(klass)
            body = klass.json_schema
            Aua.logger.warn "Found JSON schema for class: \\#{klass.name} - \\#{body.inspect}"
            # All Klass objects should provide json_schema and construct methods
            json_schema = {
              name: klass.name,
              strict: "true",
              schema: {
                **body,
                required: ["value"]
              }
            }

            Aua.logger.warn "Using schema: \\#{json_schema.inspect} for class: \\#{klass.name}"

            json_schema
          end

          def build_cast_prompt(obj, klass)
            base_prompt = <<~PROMPT
              You are an English-language runtime.
              Please provide a 'translation' of the given object in the requested type (#{klass.introspect}).
              This should be a forgiving and humanizing cast into the spirit of the target type.

              The object is '#{obj.introspect}'.
            PROMPT

            # Add type-specific guidance
            # type_guidance = if klass.aura_respond_to?(:describe)
            #                   klass.aura_send(:describe)
            #                 else
            #                   "This is a #{klass.name} type. Please provide a value that fits this type."
            #                 end
            type_guidance = case klass.name
                            when "List"
                              <<~GUIDANCE

                                This is a List type. The result should be an array of strings.
                                If the input contains multiple items (like in brackets or comma-separated),
                                preserve them as separate array elements. If it's a single item, you can
                                still make it an array, but consider if it represents multiple conceptual items.
                              GUIDANCE
                            when "Bool"
                              <<~GUIDANCE

                                This is a Boolean type. Try to be conservative but intuitive about what constitutes true vs false.
                                Return true ONLY for clearly positive, affirmative values:
                                - "yes", "true", "yep", "ok", "sure", "affirmative", "positive"

                                Return false for negative, dismissive, uncertain, or null-like values:
                                - "no", "nope", "false", "negative", "never", "null", "nihil", "void", "empty"
                                - Any form of negation or uncertainty

                                When in doubt, prefer false over true.
                              GUIDANCE
                            when "Int"
                              <<~GUIDANCE

                                This is an Integer type. Convert textual numbers to their numeric equivalents.
                                For example: "one" → 1, "twenty-three" → 23, etc.
                              GUIDANCE
                            when "Str"
                              <<~GUIDANCE

                                For numbers, you might use written-out forms (like "3.14" → "π", "1" → "one").
                              GUIDANCE
                            when "Nihil"
                              <<~GUIDANCE
                                This is a Nihil type, which represents the absence of value.
                                For instance, you might return an empty string.
                              GUIDANCE
                            else
                              ""
                            end

            # Add context for union types
            if klass.respond_to?(:union_values)
              possible_values = klass.union_values
              type_guidance += <<~ADDITIONAL

                This is a union type with these possible values:
                #{possible_values.map { |v| "- '#{v}'" }.join("\n")}

                Please select the most appropriate value from this list.
              ADDITIONAL
            end

            # base_prompt + type_guidance + "\n"
            [base_prompt, type_guidance].join("\n").strip
          end

          def builtin_inspect(obj)
            Aua.logger.info "Inspecting object: \\#{obj.inspect}"
            raise Error, "inspect requires a single argument" unless obj.is_a?(Obj)

            Aua.logger.info "Object class: \\#{obj.class}"
            Str.new(obj.introspect)
          end

          def builtin_rand(max)
            Aua.logger.info "Generating random number... (max: \\#{max.inspect})"
            rng = Random.new
            max = max.is_a?(Int) ? max.value : 100 if max.is_a?(Obj)
            Aua.logger.info "Using max value: \\#{max}"
            Aua::Int.new(rng.rand(0..max))
          end

          def builtin_time(_args)
            Aua.logger.info "Current time: \\#{Time.now}"
            Aua::Time.now
          end

          def builtin_say(arg)
            value = arg
            raise Error, "say only accepts Str arguments, got \\#{value.class}" unless value.is_a?(Str)

            $stdout.puts value.value

            Aua::Nihil.new
          end

          def builtin_ask(question)
            question = question.aura_send(:to_s) if question.is_a?(Obj) && !question.is_a?(Str)
            raise Error, "ask requires a single Str argument" unless question.is_a?(Str)

            Aua.logger.info "Asking question: \\#{question.value}"
            $stdout.puts(question.value)
            response = $stdin.gets
            Aua.logger.info "Response: \\#{response}"
            raise Error, "No response received" if response.nil?

            Str.new(response.chomp)
          end

          def builtin_chat(question)
            raise Error, "ask requires a single Str argument" unless question.is_a?(Str)

            q = question.value
            Aua.logger.info "Posing question to chat: \\#{q.inspect} (\\#{q.length} chars, \\#{q.class} => String)"
            current_conversation = Aua::LLM.chat
            response = current_conversation.ask(q)
            Aua.logger.debug "Response: \\#{response}"
            Aua::Str.new(response)
          end

          def builtin_see_url(url)
            Aua.logger.info "Fetching URL: #{url.inspect}"
            raise Error, "see_url requires a single Str argument" unless url.is_a?(Str)

            uri = URI(url.value)
            response = Net::HTTP.get_response(uri)
            handle_see_url_response(uri, response)
          end

          def handle_see_url_response(url, response)
            raise Error, "Failed to fetch URL: #{url} - #{response.message}" unless response.is_a?(Net::HTTPSuccess)

            Aua.logger.debug "Response from #{url}: #{response.body}"
            Aua::Str.new(response.body)
          end

          def builtin_typeof(obj)
            raise Error, "typeof requires a single argument" unless obj.is_a?(Obj)

            type_name = if obj.instance_variable_defined?(:@type_annotation) &&
                           obj.instance_variable_get(:@type_annotation)
                          note = obj.instance_variable_get(:@type_annotation)
                          Aua.logger.info "Type annotation found: #{note.inspect}"
                          note
                        end

            # Aua.logger.warn "No type annotation found for object: #{obj.inspect}" unless type_name

            type_name ||= case obj
                          when Int then "Int"
                          when Str then "Str"
                          when Bool then "Bool"
                          when Float then "Float"
                          when Function then "Function"
                          when ObjectLiteral then "Object"
                          when RecordObject then "Record"
                          when List then "List"
                          when Aua::Dict then "Dict"
                          when Nihil then "Nihil"
                          else obj.class.name.split("::").last
                          end
            Aua.logger.info "Type of object: #{obj.inspect} is #{type_name}"
            Str.new(type_name)
          end

          def builtin_semantic_equality(left, right)
            Aua.logger.info("builtin_semantic_equality") do
              "Semantic equality: #{left.introspect} ~= #{right.introspect}"
            end

            # Use LLM to determine semantic equality, following existing patterns
            chat = Aua::LLM.chat
            prompt = <<~PROMPT
              I want to evaluate the semantic equality between these two values.
              This should be a fuzzy and humanizing semantic operator.
              It is very, very, very important to be forgiving and humanizing in this evaluation.
              Be liberal. Do not return false owing to slightly different connotations.
              That said you must also discern obvious antonyms or clear opposites.
              Consider the broad meaning and potential intent rather than exact representation.
              Do not return true just because the items have a related context or similar structure.

              ## Semantic Equality Guidance

              Here are some significant examples of semantic equality and non-equality to help you.

              Examples of semantic equality:
              - "ok" and "okay" (nearly-identical responses)
              - "hello" and "greetings" (synonyms)
              - "house" and "home" (similar concepts)
              - "yes" and "affirmative" (similar positive responses)
              - "happy" and "joyful" (close emotions)

              Examples of semantic NON-equality:
              - "hello" and "goodbye" (opposite meanings)
              - "good" and "bad" (plain antonyms)
              - "cat" and "dog" (antithetical animals)
              - "blue" and "red" (different colors)

              ## Your Task

              The left value is '#{left.introspect}'.
              The right value is '#{right.introspect}'.

              Are these two values semantically the same or very similar in meaning?

              You must return true if they are semantically equivalent, or false if they are not.
            PROMPT

            json_schema = {
              name: "semantic_equality",
              strict: "true",
              schema: {
                type: "object",
                properties: {
                  value: {
                    type: "boolean",
                    description: "Whether the two values are semantically equivalent"
                  },
                  reason: {
                    type: "string",
                    description: "Explanation of the semantic equivalence or difference"
                  }
                },
                required: %w[value reason],
                additionalProperties: false
              }
            }

            response = chat.with_json_guidance(json_schema) do
              chat.ask(prompt)
            end

            Aua.logger.info("builtin_semantic_equality") { "Semantic equality response: #{response}" }

            # Parse response and return Bool
            result = JSON.parse(response)["value"]
            Aua::Bool.new(result)
          end

          def builtin_list_files(dir_path)
            raise Error, "list_files requires a single Str argument" unless dir_path.is_a?(Str)

            path = dir_path.value
            Aua.logger.info "Listing files in directory: #{path}"

            # Return empty list if directory doesn't exist
            unless Dir.exist?(path)
              Aua.logger.warn "Directory does not exist: #{path}"
              return Aua::List.new([])
            end

            begin
              # Get all files (not directories) in the specified directory
              files = Dir.entries(path).select do |entry|
                full_path = File.join(path, entry)
                File.file?(full_path) && !entry.start_with?('.')
              end.sort

              Aua.logger.info "Found #{files.length} files: #{files.join(', ')}"

              # Convert to Aura List of Str objects
              aura_files = files.map { |filename| Aua::Str.new(filename) }
              Aua::List.new(aura_files)
            rescue => e
              Aua.logger.error "Error reading directory #{path}: #{e.message}"
              Aua::List.new([])
            end
          end

          def builtin_load_yaml(file_path)
            raise Error, "load_yaml requires a single Str argument" unless file_path.is_a?(Str)

            path = file_path.value
            Aua.logger.info "Loading YAML file: #{path}"

            # Return nihil if file doesn't exist
            unless File.exist?(path)
              Aua.logger.warn "File does not exist: #{path}"
              return Aua::Nihil.new
            end

            begin
              require 'yaml'
              yaml_content = YAML.load_file(path)
              Aua.logger.info "Loaded YAML content: #{yaml_content.inspect}"

              # Convert Ruby hash/array structure to Aura objects
              convert_yaml_to_aura(yaml_content)
            rescue => e
              Aua.logger.error "Failed to load YAML file: #{e.message}"
              Aua::Nihil.new
            end
          end

          # Parse a YAML string and convert it to Aura objects
          def builtin_parse_yaml(yaml_str)
            begin
              require 'yaml'
              yaml_data = YAML.safe_load(yaml_str.value, permitted_classes: [Symbol, Date, Time])

              convert_yaml_to_aura(yaml_data)
            rescue YAML::SyntaxError => e
              Aua.logger.error "YAML parsing error: #{e.message}"
              raise Error, "Invalid YAML format: #{e.message}"
            end
          end


          def to_ruby(obj)
            case obj
            when Aua::Dict then obj.values.transform_values(&method(:to_ruby))
            when Aua::List then obj.values.map(&method(:to_ruby))
            when Aua::ObjectLiteral
               # debugger
               obj.fields.map do |key|
                 [key, to_ruby(obj.get_field(key))]
               end.to_h
            else
              obj.value
            end
          end

          def builtin_dump_yaml(obj)
            raise Error, "dump_yaml requires a single Obj argument" unless obj.is_a?(Obj)

            Aua.logger.info "Dumping object to YAML: #{obj.introspect}"

            # Convert Aura object to Ruby hash/array structure
            ruby_obj = to_ruby(obj)

            # Dump to YAML string
            begin
              require 'yaml'
              yaml_str = YAML.dump(ruby_obj)
              Aua.logger.info "YAML dump result: #{yaml_str.inspect}"

              Aua::Str.new(yaml_str)
            rescue => e
              Aua.logger.error "Failed to dump object to YAML: #{e.message}"
              raise Error, "Failed to dump object to YAML: #{e.message}"
            end
          end

          private

          def convert_yaml_to_aura(obj)
            case obj
            when Hash
              # Convert to Aura Dict
              aura_hash = {}
              obj.each do |key, value|
                aura_key = key.to_s
                aura_value = convert_yaml_to_aura(value)
                aura_hash[aura_key] = aura_value
              end
              Aua::Dict.new(aura_hash)
            when Array
              # Convert to Aura List
              aura_array = obj.map { |item| convert_yaml_to_aura(item) }
              Aua::List.new(aura_array)
            when String
              Aua::Str.new(obj)
            when Integer
              Aua::Int.new(obj)
            when Float
              Aua::Float.new(obj)
            when TrueClass, FalseClass
              Aua::Bool.new(obj)
            when NilClass
              Aua::Nihil.new
            else
              # For other types, convert to string
              Aua::Str.new(obj.to_s)
            end
          end
        end
      end
    end
  end
end
