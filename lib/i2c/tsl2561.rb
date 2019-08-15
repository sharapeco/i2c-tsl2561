require 'i2c'

module I2C
	module Driver
		class TSL2561

			class DeviceValue
				class Channel
					attr_accessor :val
				end

				# ch0: visible & infrared light
				# ch1: infrared light
				attr_accessor :ch0, :ch1

				def lux
					if @ch0 > 0
						irRatio = @ch1.to_f / @ch0
						if irRatio.between?(0.0, 0.52)
							return (0.0315 * @ch0) - (0.0593 * @ch0 * (irRatio ** 1.4))
						elsif irRatio.between?(0.52, 0.65)
							return (0.0229 * @ch0) - (0.0291 * @ch1)
						elsif irRatio.between?(0.65, 0.80)
							return (0.0157 * @ch0) - (0.0180 * @ch1)
						elsif irRatio.between?(0.80, 1.30)
							return (0.00338 * @ch0) - (0.00260 * @ch1)
						else
							return 0
						end
					else
						return 0
					end
				end
			end

			# I2C Bus address (low: 0x29, high: 0x49)
			I2C_ADDRESS = 0x39 # float
			
			# ported from https://github.com/adafruit/TSL2561-Arduino-Library
			# command values
			READBIT = 0x01
			
			COMMAND_BIT = 0x80 # Must be 1
			CLEAR_BIT = 0x40 # Clears any pending interrupt (write 1 to clear)
			WORD_BIT = 0x20 # 1 = read/write word (rather than byte)
			BLOCK_BIT = 0x10 # 1 = using block read/write

			CONTROL_POWERON = 0x03
			CONTROL_POWEROFF = 0x00
			
			# register
			REGISTER_CONTROL          = 0x00
			REGISTER_TIMING           = 0x01
			REGISTER_THRESHHOLDL_LOW  = 0x02
			REGISTER_THRESHHOLDL_HIGH = 0x03
			REGISTER_THRESHHOLDH_LOW  = 0x04
			REGISTER_THRESHHOLDH_HIGH = 0x05
			REGISTER_INTERRUPT        = 0x06
			REGISTER_CRC              = 0x08
			REGISTER_ID               = 0x0A
			REGISTER_CHAN0_LOW        = 0x0C
			REGISTER_CHAN0_HIGH       = 0x0D
			REGISTER_CHAN1_LOW        = 0x0E
			REGISTER_CHAN1_HIGH       = 0x0F

			# integration time type
			INTEGRATIONTIME_13MS      = 0x00    # 13.7ms
			INTEGRATIONTIME_101MS     = 0x01    # 101ms
			INTEGRATIONTIME_402MS     = 0x02     # 402ms
			
			# gain type
			GAIN_0X                   = 0x00    # No gain
			GAIN_16X                  = 0x10    # 16x gain

			# @param [Integer|String|I2C::Dev] device The I2C device id of i2c-dev, a string that points to the i2c-dev device file or an already initialized I2C::Dev instance
			# @param [Fixnum] i2c_address The i2c address of the TSL2561. Factory default is 0x39.
			def initialize(device:, i2c_address: I2C_ADDRESS)
				device = "/dev/i2c-#{device}" if device.is_a?(Integer)

				if device.is_a?(String)
					raise ArgumentError, "I2C device #{device} not found. Is the I2C kernel module enabled?" unless File.exists?(device)
					device = I2C.create(device)
				end

				raise ArgumentError unless device.is_a?(I2C::Dev)

				@device = device
				@i2c_address = i2c_address
				
				@integration = INTEGRATIONTIME_402MS
				@gain = GAIN_0X

				setGain(GAIN_16X)
			end

			# @return [DeviceValue] All channel values
			def all
				data
			end

			# @return [Float] The illuminance in lux
			def lux
				data.lux
			end

			private

			def powerOn
				write(COMMAND_BIT | REGISTER_CONTROL, CONTROL_POWERON)
			end

			def powerOff
				write(COMMAND_BIT | REGISTER_CONTROL, CONTROL_POWEROFF)
			end

			def setTiming(integration)
				setTimingAndGain(integration, @gain)
			end

			def setGain(gain)
				setTimingAndGain(@integration, gain)
			end

			def setTimingAndGain(integration, gain)
				@integration = integration
				@gain = gain
				powerOn
				write(COMMAND_BIT | REGISTER_TIMING, integration | gain)
				powerOff
			end

			def data
				# wake up
				powerOn
				
				# Wait x ms for ADC to complete
				case @integration
					when INTEGRATIONTIME_13MS
						sleep(0.014)
					when INTEGRATIONTIME_101MS
						sleep(0.102)
					else # default conversion time is 402 ms
						sleep(0.403)
				end

				# read raw data
				ch0 = read(COMMAND_BIT | WORD_BIT | REGISTER_CHAN0_LOW, 2)
				ch1 = read(COMMAND_BIT | WORD_BIT | REGISTER_CHAN1_LOW, 2)
				
				val = DeviceValue.new
				val.ch0 = ch0.unpack('S').first
				val.ch1 = ch1.unpack('S').first
				
				# TODO: scale by integration time
				# ...

				# apply gain
				if @gain == GAIN_0X
					val.ch0 = val.ch0 << 4
					val.ch1 = val.ch1 << 4
				end
				
				# sleep
				powerOff
				
				val
			end

			# write to device
			def write(reg_address, data)
				@device.write(@i2c_address, reg_address, data)
			end

			# read from device
			def read(reg_address, size = 1)
				@device.read(@i2c_address, size, reg_address)
			end
		end
	end
end
