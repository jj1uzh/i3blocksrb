#!/bin/ruby

require 'json'

class Blocks
  def initialize
    @blocks_stack = []
    @blocks = []
  end

  def publish()
    print '[', @blocks.join(', '), "],\n"
    STDOUT.flush
  end

  def push_blocks(blocks)
    @blocks_stack.push(@blocks.clone)
    @blocks = blocks
    publish
  end

  def pop_blocks()
    @blocks = @blocks_stack.pop()
    publish
  end

  def click_event(click_obj)
    @blocks
      .find {|b| b.instance.to_s == click_obj['instance']}
      &.on_click(click_obj)
  end
end
$blocks = Blocks.new

class Block
  def initialize(instance, conf)
    @command, @transformer, interval, props, onclick = conf.instance_eval {[@command, @transformer, @interval, @props, @onclick]}
    props ||= {}
    @instance = instance
    @block_obj = {instance: instance, full_text: '', **props}
    @transformer ||= proc(&:chomp)
    unless @command.nil?
      case interval
      in 'once' | :once | nil then exec_once
      in 'persist' | :persist then set_persist
      in Integer => n         then set_interval_by_secs(n)
      in Object => other      then raise "Unknown interval `#{other}` of block `#{name}`"
      end
    end
    set_onclick onclick
    regen_json
  end

  attr_reader :instance
  def to_s = @buf

  def regen_json
    @buf = JSON.generate @block_obj
  end

  def update(content)
    case content
    in String => s then @block_obj[:full_text] = s
    in Hash => h then @block_obj.merge! h
    end
    regen_json
    $blocks.publish()
  end

  def update_by_command
    warn "#{@instance} #{@transformer}"
    update @transformer[`#{@command}`]
  end

  def exec_once
    update_by_command
  rescue
    update 'ERROR'
  end

  def set_interval_by_secs(secs)
    Thread.new do
      loop {
        update_by_command
        sleep secs
      }
    rescue => e
      warn e.full_message
      update 'ERROR'
    end
  end

  def set_persist
    Thread.new do
      r, w = IO.pipe
      pid = spawn @command, out:w
      r.each chomp:true do |out|
        update @transformer[out]
      end
    rescue => e
      warn e.full_message
      update 'ERROR'
    ensure
      Process.kill :TERM, pid
    end
  end

  def push_submenu(blocks)
    warn blocks
    $blocks.push_blocks(blocks)
  end

  def pop_submenu
    $block.pop_blocks()
  end

  def set_onclick(onclick)
    fn = case onclick
         in '__back__'    then proc {|obj| pop_submenu}
         in String => cmd then proc {|obj| spawn cmd}
         in Proc => p     then proc {|obj| update p[obj]}
         in Array => a    then proc {|obj| push_submenu a}
         in nil           then proc {}
         end
    define_singleton_method 'on_click', &fn
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

  def onclick(obj = nil, &block)
    @onclick = if obj.nil? then block else obj end
  end

  def submenu(&block)
    if block.nil? then raise "#{@name}: submenu block is missing" end
    loader = ConfLoader.new
    loader.instance_eval(&block)
    back_block_conf = BlockConf.new('back')
    back_block_conf.full_text('BACK') # tmp
    back_block_conf.onclick('__back__')
    back_block = Block.new('back', back_block_conf)
    @onclick = loader.loaded_blocks + [back_block]
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

class ConfLoader
  attr_reader :loaded_blocks
  def initialize
    @loaded_blocks = []
  end

  def method_missing(name, *args, &body)
    Kernel.warn "#{name}: args are ignored" unless args.empty?
    conf = BlockConf.new(name)
    conf.instance_eval &body
    b = Block.new(name, conf)
    @loaded_blocks.push b
  end
end

def click_events
  Enumerator.new {|y|
    buf = ""
    STDIN.each_char do |c|
      buf << c
      next if c != '}' # every event is object
      begin
        parsed = JSON.parse buf
        y << parsed
        STDIN.each_char.take_while {|c| c != ','}
        buf.clear
      rescue
        next
      end
    end
  }
end

def click_events_loop
  if (i = STDIN.readchar) != '[' then raise "Invalid input: #{i}" end
  click_events.each do |obj|
    next if obj['instance'].nil?
    $blocks.click_event(obj)
  end
end

## main
begin
  conf_path, = ARGV
  conf_path ||= '~/.config/i3blocksrb/config.rb'
  puts JSON.generate ({version: 1, click_events: true})
  puts '['
  loader = ConfLoader.new
  loader.instance_eval open(File.expand_path conf_path, &:read).read
  $blocks.push_blocks(loader.loaded_blocks)
  click_events_loop
rescue SignalException
rescue => e
  warn e.full_message
ensure
  puts ']]'
end
