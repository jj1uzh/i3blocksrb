#!/bin/ruby

require 'json'

class BlockGroups
  def initialize()
    @current_group = nil
    @groups = []
    @mutex = Mutex.new
  end

  def push_group(key, group)
    @groups.push([key, group])
    @current_group = group if @current_group.nil?
  end

  def notified_update(by_group)
    @mutex.synchronize {
      draw() if by_group == @current_group
    }
  end

  def switch_group(key)
    @mutex.synchronize {
      group = @groups.assoc(key.to_sym)&.at(1)
      if group.nil?
        warn "No such group of key: #{key}"
        return
      end
      @current_group = group
      draw()
    }
  end

  def click(click_obj)
    @current_group.click(click_obj)
  end

  def draw()
    print(@current_group.to_j)
    puts(',')
    STDOUT.flush
  end
end

class BlockGroup
  def initialize(parent_groups)
    @parent_groups = parent_groups
    @blocks = []
  end

  def push(block)
    @blocks.push(block)
  end

  def notified_update()
    @parent_groups.notified_update(self)
  end

  def switch_group(key)
    @parent_groups.switch_group(key)
  end

  def click(click_obj)
    instance = click_obj['instance'].to_sym
    @blocks.find {|b| b.instance == instance}&.click(click_obj)
  end

  def to_j
    '[' + @blocks.map(&:to_j).join(',') + ']'
  end
end

class Block
  attr_reader :instance
  def initialize(instance, parent_group, conf)
    @instance = instance
    @parent_group = parent_group
    @command, @transformer, interval, props, onclick = conf.instance_eval {
      [@command, @transformer, @interval, @props || {}, @onclick]
    }

    @block_obj = {instance: instance, **props}
    @block_obj[:full_text] ||= ''
    @transformer ||= proc(&:chomp)

    unless @command.nil?
      case interval
      in 'once' | :once | nil then exec_once()
      in 'persist' | :persist then set_persist()
      in Integer => n         then set_interval_by_secs(n)
      in Object => other      then raise "Unknown interval `#{other}` of block `#{name}`"
      end
    end
    set_onclick(onclick)
    update_json_buf()
  end

  def to_j
    @buf
  end

  def update_json_buf()
    @buf = JSON.generate(@block_obj)
  end

  def update(content)
    case content
    in String => s then @block_obj[:full_text] = s
    in Hash => h then @block_obj.merge! h
    end
    update_json_buf()
    @parent_group.notified_update
  end

  def update_by_command()
    # warn "#{@instance} #{@transformer}"
    update(@transformer[`#{@command}`])
  end

  def exec_once()
    update_by_command()
  rescue
    update('ERROR')
  end

  def set_interval_by_secs(secs)
    Thread.new do
      loop {
        update_by_command()
        sleep secs
      }
    rescue => e
      warn e.full_message
      update('ERROR')
    end
  end

  def set_persist()
    Thread.new do
      r, w = IO.pipe
      pid = spawn @command, out:w
      r.each(chomp:true) {|out| update(@transformer[out])}
    rescue => e
      warn e.full_message
      update('ERROR')
    ensure
      Process.kill :TERM, pid
    end
  end

  def set_onclick(onclick)
    procs = onclick&.map {|pair|
      case pair
      in [:do_cmd, cmd]       then proc {|obj| spawn cmd}
#      in ['do_proc', p]       then proc {|obj| update p[obj]}
      in [:switch_group, key] then proc {|obj| @parent_group.switch_group(key)}
      in _                    then raise "Unexpected onclick value #{pair}"
      end
    } || []
    fn = proc {|obj| procs.each{|pc| pc.(obj)}}
    define_singleton_method('click', &fn)
  end
end

## Config DSL

class BlockConf
  def initialize(name)
    @name = name
    @props = {}
  end

  def command(cmd, &trans)
    @command = cmd
    @transformer = trans
  end

  def interval(intv)
    @interval = intv
  end

  def onclick(obj)
    @onclick = case obj
               in String => s then [[:do_cmd, s]]
               in Array => a  then a
               in Hash => h   then h
               end
  end

  valid_props = %i(full_text short_text color background border border_top border_right
                   border_left border_bottom min_width align urgent separator
                   separator_block_width markup)

  valid_props.each {|prop|
    define_method prop do |*args|
      value, = args
      unless args.size == 1 then warn "block `#{@name}`: `#{name}` needs just one arg" end
      @props[prop] = value
    end
  }
end

class ConfLoader
  class BlockLoader
    attr_reader :loaded_blocks
    def initialize(parent_group)
      @parent_group = parent_group
      @loaded_blocks = []
    end

    def method_missing(instance, *args, &body)
      conf = BlockConf.new(instance)
      conf.instance_eval(&body)
      block = Block.new(instance, @parent_group, conf)
      @loaded_blocks.push(block)
    end
  end

  class BlockGroupLoader
    def initialize(groups)
      @groups = groups
    end

    def method_missing(key, &body)
      group = BlockGroup.new(@groups)
      loader = BlockLoader.new(group)
      loader.instance_eval(&body)
      loader.loaded_blocks.each{|block| group.push(block)}
      @groups.push_group(key, group)
    end
  end

  def eval(s)
    block_groups = BlockGroups.new()
    loader = BlockGroupLoader.new(block_groups)
    loader.instance_eval(s)
    block_groups
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

def click_events_loop(block_groups)
  if (i = STDIN.readchar) != '[' then raise "Invalid input: #{i}" end
  click_events.each do |obj|
    next if obj['instance'].nil?
    block_groups.click(obj)
  end
end

## main
begin
  conf_path, = ARGV
  conf_path ||= '~/.config/i3blocksrb/config.rb'
  puts JSON.generate ({version: 1, click_events: true})
  puts '['
  block_groups = ConfLoader.new.eval(open(File.expand_path conf_path, &:read).read)
  block_groups.draw()
  click_events_loop(block_groups)
rescue SignalException
rescue => e
  warn e.full_message
ensure
  puts ']]'
end
