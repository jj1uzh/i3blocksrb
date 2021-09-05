# coding: utf-8
mem { #memとswapまとめたい
  command 'free' do |out|
    total, used = out.lines[1].split[1, 2].map(&:to_f)
    percent = used / total * 100
    color = if percent >= 80 then '#ff0000' else '#ffffff' end
    {full_text: sprintf('Mem:%2.1fGi(%2.0f%%)', used / 1048576, percent), color: color}
  end
  interval 10
}

swap {
  command 'free' do |out|
    total, used = out.lines[2].split[1, 2].map(&:to_f)
    percent = used / total * 100
    color = if percent == 0 then '#ffffff' else '#ffff00' end
    {full_text: sprintf('Swp:%2.1fGi(%2.0f%%)', used / 1048576, percent), color: color}
  end
  interval 10
}

clock {
  command "date '+%Y-%m-%d(%a) %H:%M'"
  interval 10
  color '#000000'
  background '#ffffff'
}
