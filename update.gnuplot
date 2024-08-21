set xrange [1600:0]
set terminal png
set output 'temp.png'
unset key
plot 'temp.dat' w lines lc rgb 'black'