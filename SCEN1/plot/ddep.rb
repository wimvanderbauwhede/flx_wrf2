modules=%w{flexpart_helpers multi_rddep_w}

c_modules=modules.map {|m| m+".c"}
o_modules=modules.map {|m| m+".o"}
executable="ddep2bin"

puts "Compiling programs"
`gcc -c #{c_modules.join(" ")}`
puts "Linking programs"
`gcc  #{o_modules.join(" ")} -o #{executable} `

puts `#{executable}`
