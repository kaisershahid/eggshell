module Eggshell; class ExpressionEvaluator;
class Evaluator
	def initialize(vtable, ftable)
		@vtable = vtable
		@ftable = ftable
	end

	def evaluate(struct)
		ret = nil
		struct.each do |frag|
			if frag.is_a?(Array)
				if frag[0] == :op
					
				elsif frag[0] == :op_tern
					
				elsif frag[0] == :func
					buff << frag[1] + '('
					buff << reassemble(frag[2], ',')
					buff << ')'
				elsif frag[0] == :group
					
				elsif frag[0] == :var
					
				elsif frag[0] == :index_access
					
				end
			else
				buff << s
				buff << (frag.is_a?(String) ? '"' + frag.gsub('"', '\\"') + '"' : frag)
				s = sep
			end
		end
	end
	
	# @param String|Array var If `var` is a string and contains only alphanumeric/dot characters,
	# an attempt will be made to match an exact var name with that, otherwise, it will be decomposed
	# and each part will be looked up successively.
	def get_var(var, do_ptr = false)

	end
	
	def set_var(var, val)
	end
end
end; end;