#!/usr/bin/env ruby

# Generate 100 samples
# Usage : 
# samples.rb your_tracery_bot.json

require_relative 'tracery'
require_relative 'mods-eng-basic'

include Tracery

if ARGV.length != 1
  raise 'Need file path as argument'
end

file_path = ARGV[0]
STDERR << "Reading [#{file_path}]\n"
file_content = IO.read(file_path)
parsed_file = JSON.parse(file_content)
grammar = createGrammar(parsed_file);
grammar.addModifiers(Modifiers.baseEngModifiers);

STDOUT << "\n#{grammar.flatten("#origin#")}\n\n"
