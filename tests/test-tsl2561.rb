require './libs/i2c/tsl2561'

ldev = I2C::Driver::TSL2561.new(device: 1)
p ldev.all
p ldev.lux
