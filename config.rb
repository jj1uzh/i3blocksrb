block 'free' do
  command 'free' do |out|
    out.lines[1, 2].map {|m|
      total, used = m.split[1, 2].map(&:to_f)
      sprintf('%2.1fGi(%2.0f%%)', used / 1048576, used / total * 100)
    }.join('/')
  end
  interval 5
end

block 'clock' do
  command "date '+%Y-%m-%d(%a) %H:%M'"
  interval 10
end
