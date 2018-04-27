#!/usr/bin/env ruby

require 'json'

# Draw a dependencies schema in Dot format
# https://en.wikipedia.org/wiki/DOT_(graph_description_language)
# Usage : 
# dependencies_schema.rb your_tracery_bot.json > your_tracery_bot.gv
# dot -Tsvg your_tracery_bot.gv -o your_tracery_bot.svg

if ARGV.length != 1
  raise 'Need file path as argument'
end

file_path = ARGV[0]
STDERR << "Reading [#{file_path}]\n"
file_content = IO.read(file_path)
parsed_file = JSON.parse(file_content)

# @type [Hash{String,RulesGroup}]
fragments_groups = {}

# Indicate a fragment replacement
class FragmentReplacement

  attr_reader :from_fragment, :start_position, :stop_position, :to_group_name

  # @param from_fragment [Fragment]
  # @param start_position [Integer]
  # @param stop_position [Integer]
  # @param to_group_name [String]
  def initialize(from_fragment, start_position, stop_position, to_group_name)
    @from_fragment = from_fragment
    @start_position = start_position
    @stop_position = stop_position
    @to_group_name = to_group_name
  end

end

# A rule = a line with possibly some replacements
class Rule

  attr_reader :original_value, :fragments_replacements

  # @param value [String]
  def initialize(value)
    @original_value = value

    # @type [Array{FragmentReplacement}]
    @fragments_replacements = []

    # Find all hashes (#) indexes
    hash_indexes = []
    current_index = -1
    while (current_index = value.index('#', current_index+1))
      hash_indexes << current_index
    end

    if hash_indexes.length.odd?
      raise "[#{value}] has unbalanced #"
    end

    # Create the fragments replacement from the hashes indexes
    0.upto((hash_indexes.length / 2) - 1) do |index|
      start_hash_position = hash_indexes[index * 2]
      stop_hash_position = hash_indexes[(index * 2) + 1]
      to_fragment = value[start_hash_position + 1, stop_hash_position - start_hash_position - 1]

      # process modifiers
      ['capitalize'].each do |modifier|
        if to_fragment.end_with? ".#{modifier}"
          to_fragment = to_fragment[0.. -(modifier.length+2)]
        end
      end
      fragments_replacements << FragmentReplacement.new(self, start_hash_position, stop_hash_position, to_fragment)
    end
    @posssibilities = 0
  end

  def calculate(fragments_groups)
    if @posssibilities == 0
      @posssibilities = 1
      fragments_replacements.each do |fragments_replacement|
        replacement_group = fragments_groups[fragments_replacement.to_group_name]
        @posssibilities *= replacement_group.calculate(fragments_groups)
      end
    end
    @posssibilities
  end

end

# A group of rules
class RulesGroup

  STATUS_KNOWN = 'known'
  STATUS_UNKNOWN = 'unknown'

  attr_reader :name, :dependencies, :rules
  attr_accessor :status

  #@param name [String]
  def initialize(name, status)
    @name = name
    # @type[Hash{String, RulesGroup}]
    @dependencies = {}
    @status = status
    @posssibilities = 0
    @rules = []
  end

  def calculate(fragments_groups)
    if @posssibilities == 0
      rules.each do |rule|
        @posssibilities += rule.calculate(fragments_groups)
      end
      @calculated = true
    end
    @posssibilities
  end

end

# @return [RulesGroup]
def get_or_create_rules_group(fragments_groups, group_name, will_known)
  if fragments_groups.key?(group_name)
    current_group = fragments_groups[group_name]
    if current_group.status == RulesGroup::STATUS_KNOWN
      if will_known
        raise "Fragment group already exist [#{group_name}]"
      else
        current_group
      end
    else
      if will_known
        current_group.status = RulesGroup::STATUS_KNOWN
      end
      current_group
    end
  else
    current_group = RulesGroup.new(group_name, will_known ? RulesGroup::STATUS_KNOWN : RulesGroup::STATUS_UNKNOWN)
    fragments_groups[group_name] = current_group
  end
end

parsed_file.each_pair do |current_group_name, current_group_values|
  current_rules_group = get_or_create_rules_group(fragments_groups, current_group_name, true)
  current_group_values.each do |value|
    rule = Rule.new(value)
    rule.fragments_replacements.each do |fragment_replacement|
      replacement_name = fragment_replacement.to_group_name
      unless current_rules_group.dependencies.key?(replacement_name)
        current_rules_group.dependencies[replacement_name] = get_or_create_rules_group(fragments_groups, replacement_name, false)
      end
    end
    current_rules_group.rules << rule
  end
end

# Check we have visited all the groups
fragments_groups.values.each do |current_group|
  if current_group.status == RulesGroup::STATUS_UNKNOWN
    raise "Unknown group [#{current_group.name}]"
  end
end

# Calculate the cardinality recursively
fragments_groups.values.each do |current_group|
  current_group.calculate(fragments_groups)
end

# Print a value to STDOUT without the escaping we have with p
def rw(value)
  STDOUT << "#{value}\n"
end

# Now create the graph
rw 'digraph tracery {'
rw 'compound=true;'
rw "\tgraph [rankdir=LR];"

current_group_index = 0
fragments_groups_to_id = {}

# Declare the rules
fragments_groups.each_pair do |fragment_group_name, fragment_group|
  fragments_groups_to_id[fragment_group_name] = current_group_index
  fragment_group.rules.each_with_index do |rule, rule_index|
    if rule.calculate(fragments_groups) == 1
      rw "\trule_#{current_group_index}_#{rule_index}[label=\"#{rule.original_value}\"];"
    else
      rw "\trule_#{current_group_index}_#{rule_index}[label=\"#{rule.original_value} #{rule.calculate(fragments_groups)}\"];"
    end
  end
  current_group_index+= 1
end

rw ''

# Declare the groups
fragments_groups.each_pair do |fragment_group_name, fragment_group|
  current_group_index = fragments_groups_to_id[fragment_group_name]
  rw "\tsubgraph cluster_#{current_group_index} {"
  rw "\t\tlabel=\"#{fragment_group_name} #{fragment_group.calculate(fragments_groups)}\";"
  fragment_group.rules.each_with_index do |rule, rule_index|
    rw "\t\trule_#{current_group_index}_#{rule_index};"
  end
  rw "\t}"
  current_group_index+= 1
  rw ''
end

rw ''
rw ''

# Declare the links
fragments_groups.each_pair do |fragment_group_name, fragment_group|
  current_group_index = fragments_groups_to_id[fragment_group_name]
  fragment_group.rules.each_with_index do |rule, rule_index|
    rule.fragments_replacements.each do |fragments_replacement|
      replacement_group_id = fragments_groups_to_id[fragments_replacement.to_group_name]
      rw "\trule_#{current_group_index}_#{rule_index} -> rule_#{replacement_group_id}_0 [lhead=cluster_#{replacement_group_id}];"
    end
    rw ''
  end
  rw ''
  rw ''
end

# Declare the groups
#fragments_groups.each_pair do |fragment_group_name, fragment_group|
#  fragments_groups_to_id[fragment_group_name] = current_group_index
#  rw "\tgroup_#{current_group_index} [label=\"#{fragment_group_name} #{fragment_group.calculate(fragments_groups)}\"];"
#  current_group_index+= 1
#end

rw ''

# Declare the links
#fragments_groups.values.each do |fragment_group|
#  fragment_group_id = fragments_groups_to_id[fragment_group.name]
#  fragment_group.dependencies.keys.each do |dependency|
#    dependency_id = fragments_groups_to_id[dependency]
#    rw "\tgroup_#{fragment_group_id} -> group_#{dependency_id};"
#  end
#end

rw '}'
