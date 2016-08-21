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
	def set_processor(proc)
	end

	def process(buffer, macname, args, lines, indent)
	end

	module Defaults
		class NoOpHandler
			include TMD::MacroHandler

			def set_processor(proc)
				@proc = proc
			end

			def process(buffer, macname, args, lines, indent)
				@proc._warn("couldn't find macro: #{macname}")
			end
		end	
		# Macros:
		# 
		# - `include`
		# - `capture`
		# - `var`
		class MHBasics
			include TMD::MacroHandler

			def initialize
				@capvar = nil
				@collbuff = nil
				@depth = 0
			end

			def set_processor(tmd)
				@proc = tmd
				@proc.register_macro(self, '!', 'capture', 'var', 'include', 'parse_test')
			end

			def process(buffer, macname, args, lines, depth)
				if macname == '!'
					
				elsif macname == 'capture'
					# @todo check args for fragment to parse
					return if !lines
					@proc.vars[args[0][1]] = @proc.process(lines, depth)
				elsif macname == 'var'
					# @todo support multiple vars via lines
					# @todo expand value if expression
					if args.length >= 2
						key = args[0][1]
						val = args[1]
						if val.is_a?(Array)
							if val[0] == :str
								val = val[1]
							elsif val[1] == :var
								val = @proc.vars[val[2]]
							else
								# @todo operator?
							end
						end
						@proc.vars[key] = val
					end
				elsif macname == 'include'
					paths = args[0]
					if lines && lines.length > 0
						paths = lines
					end
					do_include(paths, buffer, depth)
				end
			end

			def do_include(paths, buff, depth)
				paths = [paths] if !paths.is_a?(Array)
				# @todo check all include paths?
				paths.each do |inc|
					inc = @proc.expand_expr(inc.strip)
					checks = []
					if inc[0] != '/'
						@proc.vars[:include_paths].each do |root|
							checks << "#{root}/#{inc}"
						end
						# @todo if :include_root, expand path and check that it's under the root, otherwise, sandbox
					else
						# sandboxed root include
						if @proc.vars[:include_root]
							checks << "#{@proc.vars[:include_root]}#{inc}"
						else
							checks << inc
						end
					end

					checks.each do |inc|
						if File.exists?(inc)
							lines = IO.readlines(inc)
							buff << @proc.process(lines, depth + 1)
							@proc._debug("include: 200 #{inc}")
							break
						else
							@proc._warn("include: 404 #{inc}")
						end
					end
				end
			end
		end

		class MHControlStructures
			include TMD::MacroHandler

			def initialize
				@stack = []
			end

			def set_processor(tmd)
				@proc = tmd
				@proc.register_macro(self, 'loop', 'for', 'if', 'elsif', 'else')
			end

			def process(buffer, macname, args, lines, depth)
			end
		end
	end
end