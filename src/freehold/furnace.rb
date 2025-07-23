#!/usr/bin/env ruby

require "stringio"
require "yaml"
require "json"
require "securerandom"
require "rainbow/refinement"
require "fileutils"

# Furnace - A generalized, spatialized duel framework for card combat simulation
class Furnace
  using Rainbow

  module Text
    def self.array_to_sentence(*items)
      if items.empty?
        ""
      elsif items.length == 1
        items.first.to_s
      elsif items.length == 2
        "#{items[0]} and #{items[1]}"
      else
        "#{items[0..-2].join(", ")} and #{items.last}"
      end
    end
  end

  class Effect < Data.define(:type, :on_impact, :aspect, :damage, :lifegain, :duration, :configuration)
    # effect dsl
    class DSL
      class Location
        def initialize(pos, combat)
          @position = pos
          @combat = combat
        end

        def damage(amount)
          @combat.apply_damage(@position, amount)
        end
      end

      class CardGroup < Array
        def initialize(cards)
          super(cards)
        end

        def alive?
          any?(&:alive?)
        end

        def dead?
          none?(&:alive?)
        end

        def middle
          x_coords = map { |c| c.position.x }
          y_coords = map { |c| c.position.y }

          mid_x = (x_coords.min + x_coords.max) / 2.0
          mid_y = (y_coords.min + y_coords.max) / 2.0

          Position.new(mid_x.round, mid_y.round)
        end

        # we want a clustering, on a scale of 1-5, indicating how far apart the cards are in the battle space
        # if they're all adjacent, it's 5, if they're all scattered, it's 1
        # def clustering
        # end

        # def clustered?
        # end

        def to_s
          map(&:to_s).join(", ")
        end
      end

      ############ DSL Methods ############

      def initialize(combat, card)
        @combat = combat
        @card = card
      end

      def condition(expr) = process(expr)
      def target(expr)    = process(expr)
      def apply(expr, target)
        # process(expr)
        @active_target = target
        ret = instance_eval(expr)
        @active_target = nil

        ret
      end

      private

      def enemies
        CardGroup.new(@combat.combatants.select { |c| c.alive? && c.alignment != @card.alignment })
      end

      def spot
        Location.new(@active_target, @combat)
      end

      def process(expression)
        return false unless expression
        ret = instance_eval(expression)
        puts "[DSL] Processing expression: #{expression.inspect} => #{ret.inspect}"
        ret
      end
    end
  end

  Ability = Data.define(:trigger, :target, :condition, :effects) do
  end

  Action = Data.define(:type, :card, :target) do
  end

  class CardBody

    def initialize(abilities: [])
      @abilities = abilities
    end

    def any?
      @abilities.any?
    end

    def each(&block)
      @abilities.each(&block)
    end

    # note this only works if we _don't_ do compiled IR to avoid parsing strings at runtime
    def friendly_text
      body_items = []
      @abilities.map do |ability|
        ability_text = StringIO.new
        if ability.trigger
          ability_text << "When #{ability.trigger}, "
        end

        if ability.condition
          ability_text << "if #{ability.condition}, "
        end

        ability_text << "target #{ability.target} with " if ability.target

        # ability.effects.each do |effect|
        #   ability_text << effect # "#{effect} "
        #   # effect_list = []
        #   # if effect.damage
        #   #   effect_list << " hits for #{effect.damage} damage"
        #   # end
        #   # if effect.lifegain
        #   #   effect_list << " heals you for #{effect.lifegain} life"
        #   # end
        #   #ability_text << effect_list.join(" and ")
        # end
        ability_text << Text.array_to_sentence(*ability.effects)
        body_items << ability_text.string
      end

      body_items #.join(". ") + "."
    end

    def self.parse(ability_data = [])
      puts "Parsing abilities: #{ability_data.inspect}"
      abilities = ability_data.map do |ability|
        effect = ability['effect']
        # fx = ability['effects'].map do |effect|
        #   Effect.new(
        #     type: effect['type'],
        #     on_impact: effect['on_impact'],
        #     aspect: effect['aspect'],
        #     damage: effect['damage'],
        #     lifegain: effect['lifegain'],
        #     duration: effect['duration'],
        #     configuration: effect['configuration'] || {}
        #   )
        # end

        # compile to mini-ir
        # trigger = ->(combat, card) { card.instance_eval(ability['trigger'], combat) if ability['trigger'] }
        # target = ->(combat, card) { card.instance_eval(ability['target'], combat) if ability['target'] }
        # condition = ->(combat,card) { card.instance_eval(ability['condition'], combat) if ability['condition'] }
        # effects = ->(combat, card) { fx.each { |effect| card.instance_eval("effect_#{effect['type']}", combat) } }
        Ability.new(#trigger:, target:, condition:, effects:)
          trigger: ability['trigger'],
          target: ability['target'],
          condition: ability['condition'],
          effects: [effect]
        )
      end
      new(abilities:)
    end
  end

  class RulesEngine
    def gather_events(combat)
      @events ||= {}
      living = combat.combatants.select(&:alive?)
      @events[combat.turn_count] ||= living.map do |card|
        combat.take_spatial_turn(card)
      end
    end

    def movement_phase(combat)
      # Decide and collect moves for all units
      gather_events(combat).select do |event|
        event.is_a?(Array) && event.first == :advance
      end
    end

    def action_phase(combat)
      # Decide and collect attacks for all units
      gather_events(combat).select do |event|
        event.is_a?(Array) && event.first == :attack
      end
    end

    def resolution_phase(combat, attacks)
      # Apply all attacks, resolve damage, check defeats
      attacks.each do |event|
        if event.is_a?(Array) && event.first == :attack
          attacker = event[1]
          target = event[2][:target]
          combat.attack(attacker, target)
        end
      end
    end
  end

  # Event logging for structured output
  class EventLogger
    attr_reader :events

    def initialize(mode: :verbose, output: $stdout)
      @mode = mode # :verbose, :events, :silent
      @output = output
      @events = []
      @start_time = Time.now
    end

    def log_event(type, data = {})
      timestamp = Time.now
      event = {
        type: type,
        timestamp: timestamp.iso8601,
        elapsed: ((timestamp - @start_time) * 1000).round(2),
        **data
      }

      @events << event

      case @mode
      when :events
        @output.puts event.to_json
      when :verbose
        @output.puts format_verbose_event(event)
      end
    end

    def save_yaml_log(filename, metadata = {})
      FileUtils.mkdir_p("logs")

      log_data = deep_stringify_keys({
                                       duel_id: metadata[:combat_id] || "unknown",
                                       participants: metadata[:participants] || [],
                                       metadata: {
                                         started_at: @start_time.iso8601,
                                         ended_at: Time.now.iso8601,
                                         duration_ms: @events.last&.dig(:elapsed) || 0,
                                         **metadata.except(
                                           :participants
                                         )
                                       },
                                       events: @events,
                                       summary: generate_summary,
                                       result: {
                                         winners: metadata[:winners] || [],
                                         victor_name: metadata[:victor_name] || "unknown",
                                         rounds: @events.count { |e| e[:type] == :turn_start },
                                         ended_by: metadata[:ended_by] || "elimination"
                                       },
                                       metrics: {
                                         total_damage_dealt: @events.select do |e|
                                           e[:type] == :attack
                                         end.sum { |e| e[:damage] || 0 }
                                       }
                                     })

      File.write("logs/#{filename}", YAML.dump(log_data))
      log_event(:log_saved, { filename: "logs/#{filename}" })
    end

    private

    def deep_stringify_keys(obj)
      case obj
      when Hash
        obj.each_with_object({}) do |(k, v), result|
          result[k.to_s] = deep_stringify_keys(v)
        end
      when Array
        obj.map { |e| deep_stringify_keys(e) }
      else
        obj
      end
    end

    def format_verbose_event(event)
      case event[:type]
      when :combat_setup
        lines = ["=== Combat Setup ==="]
        event[:combatants].each_with_index do |c, i|
          char = c[:name][0].upcase
          lines << "  #{i + 1}. #{c[:name]} [#{c[:faction]}/#{c[:moiety]}] ATK:#{c[:attack]} HP:#{c[:hp]} DEF:#{c[:defense]} → [#{char}:HP]"
        end
        lines.join("\n")
      when :unit_placed
        "  #{event[:unit]} positioned at (#{event[:position].join(",")})"
      when :combat_start
        "=== Combat Begin ==="
      when :turn_start
        "--- Turn #{event[:turn]} ---"
      when :move
        "  #{event[:unit]} moves from (#{event[:from].join(",")}) → (#{event[:to].join(",")})"
      when :move_blocked
        "  #{event[:unit]} cannot move (blocked)"
      when :attack
        "  #{event[:attacker]} attacks #{event[:target]} for #{event[:damage]} damage"
      when :defeat
        "  #{event[:unit]} is defeated!"
      when :combat_end
        "=== Combat End ==="
      when :victory
        "Victory: #{event[:winners].join(", ")}\nDefeated: #{event[:losers].join(", ")}"
      when :log_saved
        "📋 Combat log saved to: #{event[:filename]}"
      else
        ""
      end
    end

    def generate_summary
      combat_events = @events.select { |e| e[:type] == :attack }
      total_damage = combat_events.sum { |e| e[:damage] || 0 }

      {
        total_turns: @events.count { |e| e[:type] == :turn_start },
        total_attacks: combat_events.size,
        combat_duration_ms: @events.last&.dig(:elapsed) || 0
      }
    end
  end

  # Represents a card in combat
  class Card
    attr_reader :id, :name, :faction, :moiety, :body_type, :max_hp, :abilities
    attr_accessor :hp, :position, :alignment

    def initialize(data)
      @id = data["id"]
      @name = data["name"]
      @faction = data["faction"]
      @moiety = data["moiety"]
      @body_type = data["body_type"]
      @stats = data["stats"] || {}
      @hp = @stats["hp"] || 10
      @max_hp = @hp
      @attack = @stats["attack"] || 5
      @defense = @stats["defense"] || 0
      @position = nil
      @abilities = CardBody.parse(data["abilities"] || [])
      puts "Card created: #{name} (#{faction}/#{moiety}) -- #{@abilities.friendly_text}" # if @abilities.any?
      @alignment = SecureRandom.uuid # Unique identifier for combat alignment

      # moiety || faction # Basic alignment = moiety, fallback to faction
    end

    def attack_power
      @attack
    end

    def defense_power
      @defense
    end

    def alive?
      @hp > 0
    end

    def dead?
      !alive?
    end

    def take_damage(damage)
      actual_damage = [damage - defense_power, 0].max
      @hp = [@hp - actual_damage, 0].max
      actual_damage
    end

    def to_s
      "#{name} (#{hp}/#{max_hp})"
    end

    def detailed_info
      "#{name} [#{faction}/#{moiety}] ATK:#{attack_power} HP:#{hp}/#{max_hp} DEF:#{defense_power}"
    end

    def enemies(combat)
      combat.combatants.select { |c| c.alive? && c.alignment != alignment }
    end
  end

  # Represents a position on the combat grid
  class Position
    attr_reader :x, :y

    def initialize(x, y)
      @x = x
      @y = y
    end

    def distance_to(other)
      Math.sqrt(((x - other.x)**2) + ((y - other.y)**2))
    end

    def manhattan_distance_to(other)
      (x - other.x).abs + (y - other.y).abs
    end

    def adjacent_positions(max_x: 2, max_y: 2)
      [
        Position.new(x - 1, y), Position.new(x + 1, y),
        Position.new(x, y - 1), Position.new(x, y + 1)
      ].select { |pos| pos.x >= 0 && pos.x < max_x && pos.y >= 0 && pos.y < max_y }
    end

    def ==(other)
      x == other.x && y == other.y
    end

    def eql?(other)
      self == other
    end

    def hash
      [x, y].hash
    end

    def to_s
      "(#{x},#{y})"
    end
  end

  # Combat grid for spatial simulation
  class Grid
    attr_reader :width, :height, :cards

    def initialize(width: 3, height: 2)
      @width = width
      @height = height
      @cards = {}
      @scalar_fields = {
        heat: Array.new(height) { Array.new(width, 0.0) },
        pressure: Array.new(height) { Array.new(width, 1.0) },
        visibility: Array.new(height) { Array.new(width, 1.0) }
      }
    end

    def place_card(card, position)
      if valid_position?(position) && empty_at?(position)
        @cards[position] = card
        card.position = position
        true
      else
        false
      end
    end

    def card_at(position)
      @cards[position]
    end

    def empty_at?(position)
      !@cards.has_key?(position)
    end

    def valid_position?(position)
      position.x >= 0 && position.x < width && position.y >= 0 && position.y < height
    end

    def move_card(from_pos, to_pos)
      return false unless valid_position?(to_pos) && empty_at?(to_pos)

      card = @cards.delete(from_pos)
      return false unless card

      place_card(card, to_pos)
    end

    def find_card(card)
      @cards.find { |pos, c| c == card }&.first
    end

    def cards_with_positions
      @cards.to_a
    end

    def display
      puts "Combat Grid (#{width}x#{height}):"
      puts "  " + ("=" * ((width * 6) - 1))
      # print_hp_grid!
      print_rogue_grid!
      puts "  " + ("=" * ((width * 6) - 1))
      puts
    end

    def print_hp_grid!
      footnotes = {}

      (0...height).each do |y|
        row_display = (0...width).map do |x|
          pos = Position.new(x, y)
          card = card_at(pos)
          if card
            # Use first letter of name + HP for better identification
            char = card.name[0].upcase
            footnotes[char] ||= card.name
            hp_display = format("%2d", card.hp)
            faction_color = case card.faction&.downcase
                            when "white" then :white
                            when "black" then :black
                            when "red" then :red
                            when "blue" then :blue
                            when "green" then :green
                            else :default
                            end
            "[#{char}:#{hp_display}]".color(faction_color)
          else
            " --- "
          end
        end
        puts "  #{row_display.join(" ")}"
      end

      puts footnotes.map { |char, name| "#{char}: #{name}" }.join("  ").color(:cyan)
    end

    def print_rogue_grid!
      (0...height).each do |y|
        row_display = (0...width).map do |x|
          pos = Position.new(x, y)
          card = card_at(pos)
          if card
            char = card.name[0]
            card.hp < 10 ? char.downcase : char.upcase
          else
            "."
          end
        end
        puts "  #{row_display.join}"
      end
    end
  end


  # Combat simulation engine
  class Combat

    attr_reader :grid, :combatants, :logger, :turn_count

    def initialize(cards, spatial: true, logger: nil)
      @combatants = cards.map { |data| Card.new(data) }
      @spatial = spatial
      @grid = spatial ? Grid.new : nil
      @logger = logger || EventLogger.new
      @turn_count = 0
      @results = {}

      setup_combat
    end

    def setup_combat
      @logger.log_event(:combat_setup, {
                          spatial: @spatial,
                          combatants: @combatants.map do |c|
                            {
                              name: c.name,
                              faction: c.faction,
                              moiety: c.moiety,
                              hp: c.hp,
                              attack: c.attack_power,
                              defense: c.defense_power
                            }
                          end
                        })

      return unless @spatial

      # Place cards on grid - simple positioning for now
      positions = [
        Position.new(0, 0), Position.new(2, 0),  # corners of first row
        Position.new(0, 1), Position.new(2, 1)   # corners of second row
      ]

      @combatants.each_with_index do |card, i|
        pos = positions[i % positions.length]
        @grid.place_card(card, pos)
        @logger.log_event(:unit_placed, {
                            unit: card.name,
                            position: [pos.x, pos.y]
                          })
      end
    end

    def rules_engine
      @rules_engine ||= RulesEngine.new
    end

    def run_combat
      until combat_over?
        @turn_count += 1
        moves = rules_engine.movement_phase(self)
        apply_moves(moves)
        attacks = rules_engine.action_phase(self)
        rules_engine.resolution_phase(self, attacks)
        logger.log_event(:turn_start, { turn: turn_count })
        @grid.display if @spatial && @logger.instance_variable_get(:@mode) == :verbose
        # sleep 0.2
      end
      finalize_combat
    end

    def apply_moves(move_list)
      move_list.each do |event|
        if event.is_a?(Array) && event.first == :advance
          puts "Moving #{event[1].name} towards #{event[2][:target].name}"
          card = event[1]
          target = event[2][:target]
          move_towards(card, target)
        else
          raise "Invalid move event: #{event.inspect}"
        end
      end
    end

    def evaluate_condition(condition, card)
      puts "Evaluating condition: #{condition.inspect} for card: #{card.name}"
      if condition
        Effect::DSL.new(self, card).condition(condition)
      else
        true
      end
    end

    def resolve_targets(target, card)
      puts "Resolving targets for #{card.name} with target: #{target.inspect}"
      [Effect::DSL.new(self, card).target(target)]
    end

    def apply_effect(effect, card, target)
      puts "Applying effect: #{effect.inspect} from #{card.name} to #{target}"
      Effect::DSL.new(self, card).apply(effect, target)
    end

    def execute_abilities(card)
      card.abilities.each do |ability|
        next unless evaluate_condition(ability.condition, card)
        targets = resolve_targets(ability.target, card)
        ability.effects.each do |effect|
          targets.each do |target|
            apply_effect(effect, card, target)
          end
        end
      end
    end

    def take_spatial_turn(card)
      if card.abilities.any?
        effect_actions = execute_abilities(card)
        if effect_actions.any?
          return effect_actions
        end
      end

      enemies = @combatants.select { |c| c.alive? && c.alignment != card.alignment }
      return if enemies.empty?

      # Simple AI: move towards nearest enemy and attack if adjacent
      nearest_enemy = find_nearest_enemy(card, enemies)
      return unless nearest_enemy

      card_pos = @grid.find_card(card)
      enemy_pos = @grid.find_card(nearest_enemy)

      # Check if we can attack (adjacent)
      distance = card_pos.manhattan_distance_to(enemy_pos)

      if distance <= 1
        # attack(card, nearest_enemy)
        # [ :attack, card, target: nearest_enemy ]
        Action[:attack, card, nearest_enemy ]
      else
        # Try to move closer
        # move_towards(card, nearest_enemy)
        # [ :advance, card, target: nearest_enemy ]
        Action[:advance, card, nearest_enemy]
      end
    end

    def take_simple_turn(card)
      enemies = @combatants.select { |c| c.alive? && c.alignment != card.alignment }
      return if enemies.empty?

      # Simple AI: attack random enemy
      target = enemies.sample
      attack(card, target)
    end

    def find_nearest_enemy(card, enemies)
      card_pos = @grid.find_card(card)
      enemies.min_by do |enemy|
        enemy_pos = @grid.find_card(enemy)
        card_pos.manhattan_distance_to(enemy_pos)
      end
    end

    def move_towards(card, target)
      card_pos = @grid.find_card(card)
      target_pos = @grid.find_card(target)

      # Find best adjacent position to move to
      adjacent_positions = card_pos.adjacent_positions
      best_pos = adjacent_positions
                 .select { |pos| @grid.empty_at?(pos) }
                 .min_by { |pos| pos.manhattan_distance_to(target_pos) }

      if best_pos
        @grid.move_card(card_pos, best_pos)
        @logger.log_event(:move, {
                            unit: card.name,
                            from: [card_pos.x, card_pos.y],
                            to: [best_pos.x, best_pos.y],
                            target: target.name
                          })
      else
        @logger.log_event(:move_blocked, {
                            unit: card.name,
                            position: [card_pos.x, card_pos.y],
                            target: target.name
                          })
      end
    end

    def apply_damage(position, amount)
      cards = @grid.cards_with_positions
      card = cards.find { |pos, c| pos == position }&.last
      return unless card

      actual_damage = card.take_damage(amount)
      @logger.log_event(:damage_applied, {
                          unit: card.name,
                          position: [position.x, position.y],
                          damage: actual_damage,
                          hp_before: card.hp + actual_damage,
                          hp_after: card.hp
                        })

      if card.dead?
        @logger.log_event(:unit_defeated, {
                            unit: card.name,
                            position: [position.x, position.y]
                          })
      end

      actual_damage
    end

    def attack(attacker, defender)
      damage = attacker.attack_power
      actual_damage = defender.take_damage(damage)

      @logger.log_event(:attack, {
                          attacker: attacker.name,
                          target: defender.name,
                          damage: actual_damage,
                          target_hp_before: defender.hp + actual_damage,
                          target_hp_after: defender.hp,
                          positions: if @spatial
                                       {
                                         attacker: @grid.find_card(attacker)&.then { |p| [p.x, p.y] },
                                         target: @grid.find_card(defender)&.then { |p| [p.x, p.y] }
                                       }
                                     else
                                       nil
                                     end
                        })

      return unless defender.dead?

      @logger.log_event(:defeat, {
                          unit: defender.name,
                          defeated_by: attacker.name
                        })
      record_result(attacker, defender)
    end

    def combat_over?
      # Combat ends when only one alignment remains
      living_alignments = @combatants.select(&:alive?).map(&:alignment).uniq
      living_alignments.length <= 1
    end

    def finalize_combat
      winners = @combatants.select(&:alive?)
      losers = @combatants.select(&:dead?)

      @logger.log_event(:combat_end, {
                          turns: @turn_count,
                          winners: winners.map(&:name),
                          losers: losers.map(&:name),
                          final_state: @combatants.map do |c|
                            {
                              name: c.name,
                              hp: c.hp,
                              alive: c.alive?,
                              position: @spatial ? @grid.find_card(c)&.then { |p| [p.x, p.y] } : nil
                            }
                          end
                        })

      if winners.empty?
        result_type = "draw"
      else
        result_type = "victory"
        @logger.log_event(:victory, {
                            winners: winners.map(&:name),
                            losers: losers.map(&:name)
                          })
      end

      # Save detailed YAML log
      combat_id = generate_combat_id.gsub(/[^a-zA-Z0-9_]/, "_")
      victor_name = if winners.empty?
                      "Draw"
                    else
                      winners.map(&:name).join(", ")
                    end

      @logger.save_yaml_log("#{combat_id}.yaml", {
                              combat_id: combat_id,
                              result_type: result_type,
                              spatial: @spatial,
                              winners: winners.map(&:name),
                              victor_name: victor_name,
                              ended_by: winners.empty? ? "timeout" : "elimination",
                              participants: @combatants.map do |c|
                                {
                                  name: c.name,
                                  faction: c.faction,
                                  moiety: c.moiety,
                                  initial_hp: c.max_hp,
                                  final_hp: c.hp
                                }
                              end
                            })
    end

    def record_result(winner, loser)
      @results[winner.name] = (@results[winner.name] || 0) + 1
      @results[loser.name] = (@results[loser.name] || 0) - 1
    end

    def results
      # Return mapreduce-friendly results
      final_results = {}

      living_cards = @combatants.select(&:alive?)
      dead_cards = @combatants.select(&:dead?)

      living_cards.each { |card| final_results[card.name] = 1 }
      dead_cards.each { |card| final_results[card.name] = -1 }

      final_results
    end

    private

    def generate_combat_id
      participants = @combatants.map(&:name).sort.join("_vs_")
      timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
      "combat_#{participants}_#{timestamp}"
    end
  end

  # Main furnace controller
  def initialize(cards_dir: "cards")
    @cards_dir = cards_dir
    @available_cards = []
    @factions = {}
    load_cards
  end

  def load_cards
    factions = ["white", "black"]

    factions.each do |faction|
      pattern = File.join(@cards_dir, faction, "*.yaml")
      Dir.glob(pattern).each do |file_path|
        begin
          card_data = YAML.load_file(file_path)
          if card_data && card_data["stats"]
            @available_cards << card_data
            @factions[faction] ||= []
            @factions[faction] << card_data["name"]
          else
            puts "Warning: Skipping invalid card file #{file_path}".color(:yellow)
          end
        rescue StandardError => e
          puts "Warning: Could not load #{file_path}: #{e.message}".color(:yellow)
        end
      end
    end

    puts "Loaded #{@available_cards.length} cards".color(:green)
  end

  def random_cards(count = 2)
    @available_cards.sample(count)
  end

  def find_cards_by_name(*names)
    names.map do |name|
      card = @available_cards.find { |c| c["name"]&.downcase == name.downcase }
      unless card
        warn "Card not found: #{name}".color(:red)
        exit 1
      end
      card
    end
  end

  def list_cards(limit = 10)
    puts "Available cards (showing #{limit}):".color(:cyan)
    @available_cards.first(limit).each_with_index do |card, i|
      stats = card["stats"] || {}
      puts "  #{i + 1}. #{card["name"]} [#{card["faction"]}] ATK:#{stats["attack"]} HP:#{stats["hp"]} DEF:#{stats["defense"]}"
    end
    puts "... and #{[@available_cards.length - limit, 0].max} more" if @available_cards.length > limit
  end

  def run_duel(*card_names, spatial: true, logger: nil)
    cards = if card_names.empty?
              unless logger&.instance_variable_get(:@mode) == :events
                puts "No cards specified, selecting 2 random cards...".color(:blue)
              end
              random_cards(2)
            else
              find_cards_by_name(*card_names)
            end

    logger ||= EventLogger.new

    puts "Initiating duel...".color(:green).bright unless logger.instance_variable_get(:@mode) == :events

    combat = Combat.new(cards, spatial: spatial, logger: logger)
    combat.run_combat

    unless logger.instance_variable_get(:@mode) == :events
      puts "Results:".color(:cyan).bright
      pp combat.results
    end

    combat.results
  end
end

# CLI interface
if __FILE__ == $0
  using Rainbow

  furnace = Furnace.new

  # Parse logging mode
  log_mode = if ARGV.include?("--events")
               :events
             elsif ARGV.include?("--silent")
               :silent
             else
               :verbose
             end

  case ARGV[0]
  when "list"
    limit = ARGV[1]&.to_i || 10
    furnace.list_cards(limit)
  when "duel"
    spatial = !ARGV.include?("--nonspatial")
    logger = Furnace::EventLogger.new(mode: log_mode)
    card_names = ARGV[1..-1].reject { |arg| arg.start_with?("--") }
    furnace.run_duel(*card_names, spatial: spatial, logger: logger)
  when "random"
    count = ARGV[1]&.to_i || 2
    spatial = !ARGV.include?("--nonspatial")
    logger = Furnace::EventLogger.new(mode: log_mode)
    cards = furnace.random_cards(count)

    puts "Selected random cards: #{cards.map { |c| c["name"] }.join(", ")}".color(:blue) unless log_mode == :events

    combat = Furnace::Combat.new(cards, spatial: spatial, logger: logger)
    combat.run_combat

    pp combat.results unless log_mode == :events
  else
    puts <<~USAGE
      Furnace - Card Combat Simulator

      Usage:
        ruby furnace.rb list [limit]                           # List available cards
        ruby furnace.rb duel [card1] [card2] ... [options]     # Run duel with specific cards
        ruby furnace.rb random [count] [options]               # Run duel with random cards

      Options:
        --nonspatial     Use non-spatial combat (no grid)
        --events         Output JSONL events to stdout
        --silent         No output (except YAML logs)

      Examples:
        ruby furnace.rb list 20
        ruby furnace.rb duel "Test Warrior" "Military Behemoth"
        ruby furnace.rb random 4 --events
        ruby furnace.rb random 2 --nonspatial --silent
    USAGE
  end
end
