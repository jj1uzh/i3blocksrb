# coding: utf-8
# xtitle {
#   command 'xtitle -s'
#   interval :persist
# }

main {
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
    onclick 'gnome-system-monitor'
  }

  clock {
    command "date '+%Y-%m-%d(%a) %H:%M'"
    interval 10
  }

  eject {
    full_text '⏏'
    onclick 'eject cdrom'
  }

  exit_menu {
    full_text '🔌'
    onclick ({switch_group: 'exit_menu'})
  }
}

exit_menu {
  exit_i3 {
    full_text 'Exit i3'
    onclick 'i3-msg exit'
  }

  lock {
    full_text 'Lock'
    onclick ({do_cmd: 'systemctl suspend && xsecurelock', switch_group: 'main'})
  }

  suspend {
    full_text 'Suspend'
    onclick ({do_cmd: 'systemctl suspend', switch_group: 'main'})
  }

  poweroff {
    full_text 'Poweroff'
    onclick 'poweroff'
  }

  back {
    full_text 'BACK'
    onclick ({switch_group: 'main'})
  }
}
