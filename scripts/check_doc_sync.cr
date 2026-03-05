#!/usr/bin/env crystal

def fail!(message : String) : NoReturn
  STDERR.puts "[doc-sync] ERROR: #{message}"
  exit 1
end

def require_file(path : String)
  fail!("Missing file: #{path}") unless File.file?(path)
end

def numbered_h2_sequence(path : String) : String
  pattern = /^[\t ]{0,3}##[\t ]+([0-9]+)\..*/
  numbers = [] of String

  File.each_line(path) do |line|
    if match = pattern.match(line)
      numbers << match[1]
    end
  end

  numbers.join(",")
end

ja_file = ARGV[0]? || "JA.md"
en_file = ARGV[1]? || "EN.md"

require_file(ja_file)
require_file(en_file)

ja_h2 = numbered_h2_sequence(ja_file)
en_h2 = numbered_h2_sequence(en_file)

if ja_h2 != en_h2
  fail!("Numbered H2 section sequence differs between #{ja_file} and #{en_file}")
end

puts "[doc-sync] OK: #{ja_file} and #{en_file} are structurally synchronized"
puts "[doc-sync] numbered-h2-seq match: #{ja_h2}"
