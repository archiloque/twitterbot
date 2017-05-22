#!/usr/bin/env ruby

require 'json'

# Prepare a script for consumption

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
    while (current_index = value.index('#', current_index + 1))
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

PRONOM_DEF_PREFIX_NORMAL = 'pronomdef'
PRONOM_DEF_PREFIX_UP = 'Pronomdef'
PRONOM_INDEF_PREFIX_NORMAL = 'pronomindef'
PRONOM_INDEF_PREFIX_UP = 'Pronomindef'
MASC_SUFFIX = 'masc'
FEM_SUFFIX = 'fem'
ALL_KIND = '*'
VOVELS = ['a', 'e', 'i', 'o', 'u', 'é', 'è', 'ê']
PRONOMS = [PRONOM_DEF_PREFIX_NORMAL, PRONOM_DEF_PREFIX_UP, PRONOM_INDEF_PREFIX_NORMAL, PRONOM_INDEF_PREFIX_UP]

def fetch_group_content(group_name)
  found_pronom = PRONOMS.find{|pronom| group_name.start_with?(pronom)}
  if found_pronom
    group_name = group_name[(found_pronom.length + 1) .. -1]
  end

  [FEM_SUFFIX, MASC_SUFFIX].each do |gender|
    if group_name.end_with? "_#{gender}"
      real_group_name = group_name[0... - (gender.length + 1)]
      if PARSED_FILE.key? real_group_name
        real_group_content = PARSED_FILE[real_group_name]
        unless real_group_content.is_a? Hash
          raise "Group [#{real_group_name}] is not a Hash"
        end
        unless real_group_content.key?(gender)
          raise "Group [#{real_group_name}] has no [#{gender}] content"
        end

        group_candidate = real_group_content[gender]

        if real_group_content.key?(ALL_KIND)
          group_candidate = group_candidate + real_group_content[ALL_KIND]
        end

        if found_pronom
          if found_pronom == PRONOM_DEF_PREFIX_NORMAL
            return group_candidate.collect do |item|
              found_vovel = VOVELS.find{|v| item.start_with?(v)}
              if found_vovel
                "l'#{item}"
              else
                "#{(gender == MASC_SUFFIX) ? 'le' : 'la'} #{item}"
              end
            end
          elsif found_pronom == PRONOM_DEF_PREFIX_UP
            return group_candidate.collect do |item|
              found_vovel = VOVELS.find{|v| item.start_with?(v)}
              if found_vovel
                "L'#{item}"
              else
                "#{(gender == MASC_SUFFIX) ? 'Le' : 'La'} #{item}"
              end
            end
          elsif found_pronom == PRONOM_INDEF_PREFIX_NORMAL
            return group_candidate.collect do |item|
              "#{(gender == MASC_SUFFIX) ? 'un' : 'une'} #{item}"
            end
          elsif found_pronom == PRONOM_INDEF_PREFIX_UP
            return group_candidate.collect do |item|
              "#{(gender == MASC_SUFFIX) ? 'Un' : 'Une'} #{item}"
            end
          else
            raise "Unknown pronom [#{found_pronom}]"
          end

        else
          return group_candidate
        end
      else
        raise "Unknown group [#{group_name}]"
      end
    end
  end

  if PARSED_FILE.key? group_name
    PARSED_FILE[group_name]
  else
    raise "Unknown group [#{group_name}]"
  end

end

def process_group(group_name)
  if RESULT.key? group_name
    return
  end

  STDOUT << "Processing [#{group_name}]\n"

  group_content = fetch_group_content(group_name)
  group_result = []
  group_content.each do |group_line|
    fragment = Fragment.new(group_line)
    fragment.fragments_replacements.each do |fragment_replacement|
        TO_PARSE << fragment_replacement.to_fragment_name
    end
    group_result << group_line
  end
  RESULT[group_name] = group_result
end

if ARGV.length != 1
  raise 'Need file path as argument'
end

FILE_PATH = ARGV[0]
STDERR << "Reading [#{FILE_PATH}]\n"
file_content = IO.read(FILE_PATH)
PARSED_FILE = JSON.parse(file_content)

RESULT = {}
TO_PARSE = ['origin']
until TO_PARSE.empty?
  process_group(TO_PARSE.pop)
end

File.open("#{FILE_PATH[0 ... -File.extname(FILE_PATH).length]}_prepared.json", "w") do |f|
  f.write(JSON.pretty_generate(RESULT))
end
