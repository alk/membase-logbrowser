#!/usr/bin/env ruby

require 'rubygems'
gem 'activesupport'
require 'active_support/core_ext'
require 'escape'

$raw_logs = false

class Log
  extend ActiveSupport::Memoizable

  attr_reader :reject_res

  def self.read(filename)
    filter = nil
    case filename
    when /.xz$/
      filter = 'xz -dc'
    when /.gz$/
      filter = 'gzip -dc'
    when /.bz$/
      filter = 'bzip -dc'
    end
    contents = unless filter
                 IO.read(filename)
               else
                 IO.popen("#{filter} <#{Escape.shell_single_word filename}", "r") {|f| f.read}
               end
    self.new(contents)
  end

  def initialize(contents)
    @contents = contents
    @reject_res = []
    logs_raw =  if !$raw_logs
                  raise "bad logs" unless contents =~ /^logs_node:\n-------------------------------$/

                  contents[$~.end(0)..-1].strip
                else
                  contents.strip
                end
    splitted = logs_raw.split(/^([A-Z]+ REPORT.*\n#{'='*79})/)
    if splitted[0].empty?
      splitted.shift
    end
    log_items = splitted.each_slice(2).map {|a,b| [a, (b||"").strip]}

    @log_items = log_items
  end

  def filtered_items
    @log_items.reject do |h,body|
      @reject_res.any? {|re| body =~ re}
    end.map {|pair| pair.join("\n")}
  end
  memoize :filtered_items

  ITEMS_PER_PAGE = 5000
  def pages
    items = self.filtered_items
    count = (items.size + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE
    1..count
  end
  memoize :pages

  def page_items(pageno)
    pageno = 1 if pageno.nil?
    pageno = pageno.to_i if pageno.kind_of?(String)
    range = self.pages
    pageno = [range.begin,pageno].max
    pageno = [range.end, pageno].min

    items_range = ((pageno-1)*ITEMS_PER_PAGE)...(pageno*ITEMS_PER_PAGE)
    self.filtered_items[items_range]
  end

  module REs
    CONNECT_FROM_DISALLOWED_NODE = /^\*\* Connection attempt from disallowed node/
    DOCTOR_PERIODIC = /^[a-zA-Z_@0-9.]+:ns_doctor:[0-9]+: Current node statuses:\n/
    STATS_PERIODIC = /^[a-zA-Z_@0-9.]+:stats_collector:[0-9]+: Stats for bucket ".*":\n/
    PULLING_CONFIG = /^Pulling config from: /
    JANITOR_VBUCKET_CHANGE = /^[a-zA-Z_@0-9.]+:ns_janitor:[0-9]+: Setting vbucket/
    JANITOR_KILLING_REPLICATORS = /^[a-zA-Z_@0-9.]+:ns_janitor:[0-9]+: Killing replicators for vbucket/
    DISCO_CONFIG_ALL = /^ns_node_disco_confi_events config all/
  end
end

if ARGV[0] == '--raw'
  ARGV.shift
  $raw_logs = true
end

raise "Need diag!" unless ARGV[0]
$log = Log.read(ARGV[0])

$log.reject_res << Log::REs::CONNECT_FROM_DISALLOWED_NODE
$log.reject_res << Log::REs::DOCTOR_PERIODIC
$log.reject_res << Log::REs::STATS_PERIODIC
$log.reject_res << Log::REs::PULLING_CONFIG
$log.reject_res << Log::REs::JANITOR_VBUCKET_CHANGE
$log.reject_res << Log::REs::JANITOR_KILLING_REPLICATORS
$log.reject_res << Log::REs::DISCO_CONFIG_ALL

gem 'sinatra'
require 'sinatra'

get "/" do
  response['Content-Type'] = 'text/html; charset=utf-8'
  out = <<HERE
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
<html>
<head><style>
div {overflow:auto;white-space:pre;font-family:monaco,monospace;font-size:12px;}
#pagination {position: fixed; top: 0px; width: 100%; text-align: center; z-index: 9999; padding: 3px 0; margin: 0 0;}
#pagination > * { background-color: #FFF1A8; font-size: 14px; padding: 3px 10px; margin: 0 0;}
</style></head><body>
<p id="pagination"><span>#{$log.pages.map {|i| "<a href=\"?p=#{i}\">#{i}</a>"}.join(' ')}</span></p>
<div>
HERE
  out << $log.page_items(request['p']).map {|s| escape_html(s)}.join("\n</div><div>\n")
  out << (<<'HERE')
</div></body></html>
HERE
end

get "/text" do
  response['Content-Type'] = 'text/plain; charset=utf-8'
  $log.filtered_items.join("\n\n\n")
end
