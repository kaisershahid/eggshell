# Interfaces and helper classes to have processor-friendly streams.
module Eggshell; module Stream;
	def <<(str)
	end
	
	def join(str)
	end
	
	def write(str)
	end
	
	def [](index)
	end
	
	class IOWrapper
		include Stream
		
		def initialize(stream)
			@stream = stream
			@buff = []
		end
		
		def <<(str)
			@buff << str
		end
		
		def write(str)
			@stream.write(str)
		end
		
		def join(str)
			@buff.join(str)
		end
		
		def [](index)
			@buff[index]
		end
		
		def flush
			@stream.write(@buff.join("\n"))
		end
	end
end; end