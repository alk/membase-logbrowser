#!/usr/bin/ruby

require 'pp'

class ErlParser
  class ParseError < StandardError; end

  def initialize(str)
    @str = str
  end

  def parse_error(txt)
    raise ParseError, txt
  end

if true
  def dprint(*args)
  end
  def dpp(*args)
  end
  def dputs(*args)
  end
else
  def dprint(*args)
    print(*args)
  end
  def dpp(*args)
    pp(*args)
  end
  def dputs(*args)
    puts(*args)
  end
end

  def try_match(re)
    re = Regexp.new("\\A" + (re.kind_of?(Regexp) ? re.source : re))
    dprint "trying re: #{re.inspect}, "
    dprint "at: #{(@str[0..10].inspect)}"
    rv = re.match(@str)
    if rv
      @str = $'
      dputs " succeeded: #{rv.inspect}. New prefix: #{@str[0..16].inspect}"
    else
      dputs " failed"
    end
    rv
  end

  def mark
    @str
  end

  def restore(mark)
    @str = mark
  end

  def must_match(re)
    rv = try_match(re)
    unless rv
      raise "Parse error: #{re.inspect} at #{@str[0..16].inspect}"
    end
    rv
  end

  def must(method, *args)
    rv = send(method, *args)
    unless rv
      raise "Parse error: #{method.inspect}, #{args.inspect}\nat: #{@str[0..256].inspect}"
    end
    rv
  end

  def eat_whitespace
    try_match(/\s+/)
  end

  def parse_string_inner(end_re)
    rv = ""
    dputs "parse_string_inner(#{end_re.inspect})"
    while (!try_match(end_re))
      str_fragment = try_match(/[^\\#{end_re.source}]+/m)
      escape_fragment = try_match(/\\/)
      break unless str_fragment || escape_fragment
      rv << str_fragment[0] if str_fragment
      if escape_fragment
        ch = must_match(/./)[0]
        case ch
        when 'n': rv << "\n"
        when 'r': rv << "\r"
        when '\\': rv << '\\'
        else rv << ch
        end
      end
    end
    rv
  end

  def parse_string
    eat_whitespace
    return unless try_match(/"/)
    parse_string_inner(/"/)
  end

  def parse_list_like(head, start_re, end_re, comma_re)
    eat_whitespace
    return unless try_match(start_re)
    rv = [head]
    first_term = parse_term
    if first_term
      rv << first_term
      eat_whitespace
      while (try_match(comma_re))
        rv << must(:parse_term)
        eat_whitespace
      end
    end
    must_match(end_re)
    rv
  end

  def parse_tuple
    parse_list_like(:t, /\{/, /\}/, /,/)
  end

  def parse_list
    parse_list_like(:l, /\[/, /\]/, /,/)
  end

  def parse_quoted_atom
    return unless try_match(/'/)
    parse_string_inner(/'/).intern
  end

  def parse_atom
    rv = try_match(/[a-zA-Z_][a-zA-Z_0-9]*/)
    return unless rv
    rv[0].intern
  end

  def parse_shit
    rv = try_match(/(#Port)?<[0-9.]+>/)
    return unless rv
    rv[0].intern
  end

  def parse_binary
    return unless try_match(/<</)
    rv = parse_string
    must_match(/>>/)
    rv
  end

  def parse_int
    rv = try_match(/(-)?[0-9]+/)
    return unless rv
    rv[0].to_i
  end

  def parse_term
    eat_whitespace
    parse_atom || parse_string || parse_tuple ||
      parse_list || parse_quoted_atom ||
      parse_shit || parse_int || parse_binary
  end
end

parsed_term = ErlParser.new(STDIN.readlines.join("\n")).parse_term

def unpack_e_list(list)
  raise unless list[0] == :l
  list[1..-1]
end

def unpack_e_tuple(t)
  raise unless t[0] == :t
  t[1..-1]
end

def unpack_e_pplist(rpplist, h = {})
  unpack_e_list(rpplist).each do |ppair|
    k, v = unpack_e_tuple(ppair)
    h[k] = v
  end
  h
end

processes = unpack_e_list(parsed_term).map do |ppair|
  pid, rplist = unpack_e_tuple(ppair)
  h = {:pid => pid}
  unpack_e_pplist(rplist, h)
  if h[:registered_name] == [:l]
    h[:registered_name] = nil
  end
  h[:links] = unpack_e_list(h[:links])
  h[:initial_call] = unpack_e_tuple(h[:initial_call])
  # h.delete :garbage_collection
  # h.delete :backtrace
  h
end

processes = processes.sort_by {|ph| -ph[:reductions]}

processes.each do |ph|
  puts "name: '#{ph[:registered_name]}' (#{ph[:pid]}), status: #{ph[:status]}, qlen: #{ph[:message_queue_len]}, reductions: #{ph[:reductions]}"
  puts "links: #{ph[:links].inspect}"
  puts "initcall: #{ph[:initial_call].inspect}"
  puts "-" * 100
  puts ph[:backtrace].split("\n").map {|l| l[0..160]}.join("\n")
  puts "-" * 100 + "\n\n"
end

# pp processes
