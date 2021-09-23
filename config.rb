# xtitle {
#   command 'xtitle -s'
#   interval :persist
# }

mem {
  command 'free' do |out|
    mem, swap = out.lines[1, 2].map {|line|
      kind, total, used = line.split
      used_f = used.to_f
      total_f = total.to_f
      percent = if total_f > 0 then used_f / total_f * 100 else 0 end
      [kind, used_f, total_f, percent]
    }
    mem_color = if mem[3] < 80 then 'white' else 'red' end
    swap_color = if swap[2] == 0 || swap[3] == 0 then 'white' elsif swap[3] > 70 then 'red' else 'yellow' end
    mem << mem_color
    swap << swap_color
    [mem, swap].map {|kind, used, total, percent, color|
      sprintf '<span foreground="%s">%s%2.1fGi(%.0f%%)</span>', color, kind, used / 1048576, percent
    }.join(' ')
  end
  markup 'pango'
  interval 10
}

clock {
  command "date '+%Y-%m-%d(%a) %H:%M'"
  interval 10
}
