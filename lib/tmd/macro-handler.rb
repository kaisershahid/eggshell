# Macros are extensible functions that can do a lot of things:
# 
# - include other TMD documents into current document
# - process part of a document into a variable
# - do conditional processing
# - do loop processing
# - etc.
#
# A typical macro call looks like this: `@macro(param, param, ...)` and 
# must be the first item on the line (excluding whitespace).
#
# If a macro encloses a chunk of document, it would generally look like
# this:
#
# pre. @block_macro(param, ...)
# misc content
# misc content
# @end_block_macro
#
# 
module TMD::MacroHandler
	def set_parser(tmd)
	end

	def start(macname, args, depth, buffer)
	end

	def collect(line, depth)
	end

	def finish(macname, depth)
	end

	module Defaults
		# Macros startd:
		# 
		# - `include`
		# - `capture_start`, `capture_end`
		class MHBasics
			include TMD::MacroHandler

			def initialize
				@capvar = nil
				@collbuff = nil
				@depth = 0
			end

			def set_parser(tmd)
				@tmd = tmd
			end

			def start(macname, argstr, depth, buffer)
				args = @tmd.parse_args(argstr)
				case macname
				when 'var'
					key = args[0]
					val = args[1]
					if !name
						@tmd.vars[key] = val
					end
				when 'include'
					# @todo resolve relative path
					# @todo ability to restrict absolute?
					inc = args[0]
					if inc[0] != '/'
						if @tmd.vars[:include_paths].length > 0
							inc = "#{@tmd.vars[:include_paths][0]}/#{inc}"
						end
					end
					if File.exists?(inc)
						lines = IO.readlines(inc)
						buffer << @tmd.process(lines, depth + 1)
					else
						@tmd._warn("include: not found: #{inc}")
					end
				when 'capture'
					@depth = depth
					@capvar = args[0]
					@collbuff = []
					return TMD::COLLECT
				when 'parse_test'
					@tmd._info("parse_test: #{argstr} => #{args.inspect}")
				end
			end

			def collect(line, depth)
				if line == '@capture_end' && @depth == depth
					lines = @collbuff
					@collbuff = nil
					@tmd.vars[@capvar] = @tmd.process(lines, @depth)
					@capvar = nil
					@depth = 0
					return TMD::DONE
				end

				# insert one less tab if applicable
				tabs = ''
				tabs = "\t" * (depth-1) if depth > 0
				@collbuff << "#{tabs}#{line}"
				return TMD::COLLECT
			end
		end

		class MHControlStructures
			include TMD::MacroHandler

			def initialize
				@stack = []
			end

			def set_parser(tmd)
				@tmd = tmd
			end

			def start(macname, argstr, depth, buffer)
			end

			def collect(line, depth)
			end
		end
	end
end