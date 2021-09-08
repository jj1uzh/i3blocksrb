#!/bin/ruby

require "json"

$blocks = []
def $blocks.publish
  print '[', self.join(', '), "],\n"
  STDOUT.flush
end

class Block
  def initialize(name, conf)
    @command, @transformer, interval, props = conf.instance_eval {[@command, @transformer, @interval, @props]}
    props ||= {}
    @block_obj = {instance: name, full_text: '', **props}
    @transformer ||= proc(&:chomp)
    unless @command.nil?
      case interval
      in 'once' | :once | nil ; exec_once
      in 'persist' | :persist ; set_persist
      in Integer => n         ; set_interval_by_secs(n)
      in Object => other      ; raise "Unknown interval `#{other}` of block `#{name}`"
      end
    end
    regen_json
  end

  def to_s = @buf

  def regen_json
    @buf = JSON.generate @block_obj
  end

  def update_text(command_result)
    case @transformer[command_result]
    in String => s ; @block_obj[:full_text] = s
    in Hash => h   ; @block_obj.merge! h
    end
    regen_json
    $blocks.publish
  end

  def exec_once
    update_text `#{@command}`
  end

  def set_interval_by_secs(secs)
    Thread.new do
      loop { update_text `#{@command}`; sleep secs }
    end
  end

  def set_persist
    Thread.new do
      r, w = IO.pipe
      pid = spawn @command, out:w
      r.each chomp:true, &method(:update_text)
    ensure
      Process.kill :TERM, pid
    end
  end
end

## Config DSL
class BlockConf
  def initialize(name)
    @name = name
  end

  def command(cmd, &trans)
    @command = cmd
    @transformer = trans
  end

  def interval(intv)
    @interval = intv
  end

  valid_props = %w(full_text short_text color background border border_top border_right
                   border_left border_bottom min_width align urgent separator
                   separator_block_width markup)

  valid_props.each {|prop|
    define_method prop do |*args|
      value, = args
      unless args.size == 1 then warn "block `#{@name}`: `#{name}` needs just one arg" end
      @props ||= {}
      @props[prop] = value
    end
  }
end

ConfLoader = Class.new(BasicObject) do
  def method_missing(name, *args, &body)
    Kernel.warn "#{name}: args are ignored" unless args.empty?
    conf = BlockConf.new(name)
    conf.instance_eval &body
    b = Block.new(name, conf)
    $blocks.push b
  end
end

## main
begin
  conf_path, = ARGV
  conf_path ||= '~/.config/i3blocksrb/config.rb'
  puts JSON.generate ({version: 1, click_events: true})
  puts '['
  ConfLoader.new.instance_eval open(File.expand_path conf_path, &:read).read
  $blocks.publish
  sleep
rescue SignalException
rescue => e
  warn e.full_message
ensure
  puts ']]'
end
