#!/usr/bin/env ruby

require 'json'

# Draw a dependencies schema in Dot format
# https://en.wikipedia.org/wiki/DOT_(graph_description_language)
# Usage : dependencies_schema.rb your_tracery_bot.json > your_tracery_bot.gv

if ARGV.length != 1
  raise 'Need file path as argument'
end

file_path = ARGV[0]
STDERR << "Reading [#{file_path}]\n"
file_content = IO.read(file_path)
parsed_file = JSON.parse(file_content)

# @type [Hash{String,FragmentGroup}]
fragments_groups = {}

# Indicate a fragment replacement
class FragmentReplacement

  attr_reader :from_fragment, :start_position, :stop_position, :to_fragment_name

  # @param from_fragment [Fragment]
  # @param start_position [Integer]
  # @param stop_position [Integer]
  # @param to_fragment_name [String]
  def initialize(from_fragment, start_position, stop_position, to_fragment_name)
    @from_fragment = from_fragment
    @start_position = start_position
    @stop_position = stop_position
    @to_fragment_name = to_fragment_name
  end

end

# A fragment = a line with possibly some replacements
class Fragment

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
      fragments_replacements << FragmentReplacement.new(self, start_hash_position, stop_hash_position, to_fragment)
    end

  end

end

# A group of fragments
class FragmentGroup

  STATUS_KNOWN = 'known'
  STATUS_UNKNOWN = 'unknown'

  attr_reader :name, :dependencies
  attr_accessor :status

  #@param name [String]
  def initialize(name, status)
    @name = name
    # @type[Hash{String, FragmentGroup}]
    @dependencies = {}
    @status = status
  end

end

# @return [FragmentGroup]
def get_or_create_fragment_group(fragments_groups, group_name, will_known)
  if fragments_groups.key?(group_name)
    current_group = fragments_groups[group_name]
    if current_group.status == FragmentGroup::STATUS_KNOWN
      if will_known
        raise "Fragment group already exist [#{group_name}]"
      else
        current_group
        end
    else
      if will_known
        current_group.status = FragmentGroup::STATUS_KNOWN
      end
      current_group
    end
  else
    current_group = FragmentGroup.new(group_name, will_known ? FragmentGroup::STATUS_KNOWN : FragmentGroup::STATUS_UNKNOWN)
    fragments_groups[group_name] = current_group
  end

end

parsed_file.each_pair do |name, values|
  current_group = get_or_create_fragment_group(fragments_groups, name, true)
  values.each do |value|
    fragment = Fragment.new(value)
    fragment.fragments_replacements.each do |fragment_replacement|
      replacement_name = fragment_replacement.to_fragment_name
      unless current_group.dependencies.key?(replacement_name)
        current_group.dependencies[replacement_name] = get_or_create_fragment_group(fragments_groups, replacement_name, false)
      end
    end
  end
end

# Check we have visited all the groups
fragments_groups.values.each do |current_group|
  if current_group.status == FragmentGroup::STATUS_UNKNOWN
    raise "Unknown group [#{current_group.name}]"
  end
end

# Print a value to STDOUT without the escaping we have with p
def rw(value)
  STDOUT << "#{value}\n"
end

current_group_index = 0
fragments_groups_to_id = {}

# Now create the graph
rw 'digraph tracery {'

# Declare the group
fragments_groups.keys.each do |fragment_group_name|
  fragments_groups_to_id[fragment_group_name] = current_group_index
  rw "\tgroup_#{current_group_index} [label=\"#{fragment_group_name}\"];"
  current_group_index+= 1
end

rw ''

# Declare the links
fragments_groups.values.each do |fragment_group|
  fragment_group_id = fragments_groups_to_id[fragment_group.name]
  fragment_group.dependencies.keys.each do |dependency|
    dependency_id = fragments_groups_to_id[dependency]
    rw "\tgroup_#{fragment_group_id} -> group_#{dependency_id};"
  end
end

rw '}'
