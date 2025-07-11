module Aua
  module Runtime
    class VM
      module Builtin
        class << self
          def builtin_cast(obj, target)
            raise Error, "cast requires two arguments" unless obj.is_a?(Obj)

            # GenericType extends Klass, so we can treat it as a Klass
            raise Error, "Cannot cast to non-Klass: \\#{target.inspect}" unless target.is_a?(Klass)

            klass = target
            # Generic casting using LLM + JSON schema
            Aua.logger.info("builtin_cast") do
              "Casting object: \\#{obj.inspect} to class: \\#{klass.inspect} (\\#{klass.name} annotated as '#{klass.type_annotation}')"
            end
            chat = Aua::LLM.chat
            ret = chat.with_json_guidance(schema_for(klass)) do
              chat.ask(build_cast_prompt(obj, klass))
            end
            Aua.logger.info "Response from LLM: \\#{ret.inspect}"
            value = JSON.parse(ret)["value"]
            result = klass.construct(value)
            Aua.logger.info "Cast result: \\#{result.inspect} (\\#{result.class})"

            # For generic types, set the type annotation
            if klass.is_a?(Aua::Runtime::GenericType)
              type_annotation = klass.introspect
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

                                This is a Boolean type.
                                Return true for positive, affirmative, or 'yes-like' values
                                (like "yes", "true", "yep", "ok", "sure", etc.) and false for negative, dismissive,
                                or 'no-like' values (like null, false, or strings like "no", "nope", "nah", "never", etc.).
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

            type_name = if obj.instance_variable_defined?(:@type_annotation) && obj.instance_variable_get(:@type_annotation)
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
        end
      end
    end
  end
end
