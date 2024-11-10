set terminal png
set output 'temp.png'
unset key

# 日光燈校正線
$fl_lamp<<EOFL
546.5 1000
546.5 6000

611.6 1000
611.6 6000
EOFL

#plot 'temp.dat' u ($0):($1) w lines lc rgb 'black'
plot 'temp.dat' u (293.876563529884 + (0.340003060626112) * ($0**1) + (1.1769490025454e-05) * ($0**2) + (-5.31645630207678e-09) * ($0**3)):($1) w lines lc rgb 'black', \
$ fl_lamp w lines
