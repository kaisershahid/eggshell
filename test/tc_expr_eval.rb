require 'test/unit/testcase'

class Eggshell_TestExprEval < Test::Unit::TestCase
	EE = Eggshell::ExpressionEvaluator

	@@OPS_BASIC_STRUCT = {
		"1 + 2" => [[:op, "+", 1, 2]],
		"(1 + 2)" => [[:op, "+", 1, 2, :group]],
		"(1 + 2) + 3" => [[:op, "+", [:op, "+", 1, 2, :group], 3]],
		"(1 + 2)+(3/4)" => [[:op, "+", [:op, "+", 1, 2, :group], [:op, "/", 3, 4, :group]]],
		"(1 + 2)+3/4" => [[:op, "+", [:op, "+", 1, 2, :group], [:op, "/", 3, 4]]],
		"fn(1 + 2, 3)" => [[:fn, "fn", [[:op, "+", 1, 2], 3]]],
		"fn(1 + 2)+3/4" => [[:op, "+", [:fn, "fn", [[:op, "+", 1, 2]]], [:op, "/", 3, 4]]],
		"-4 + 1" => [[:op, '+', -4, 1]],
		"-bees + 1" => [[:op, '+', [:op, '-', 0, [:var, 'bees'], :group], 1]],
		"1 - 3 / 3" => [[:op, '-', 1, [:op, '/', 3, 3]]],
		"1 - 3 / 3 + 4" => [[:op, '+', [:op, '-', 1, [:op, '/', 3, 3]], 4]],
		"fn('string', var1 + var2)" => [[:fn, 'fn', ['string', [:op, '+', [:var, 'var1'], [:var, 'var2']]]]],
		"fn(1 + 2 + 3)" => [[:fn, 'fn', [[:op, '+', 1, [:op, '+', 2, 3]]]]],
		"fn(1 + 2 + 3 / var)" => [[:fn, 'fn', [[:op, '+', 1, [:op, '+', 2, [:op, '/', 3, [:var, 'var']]]]]]],
		"fn() {" => [[:fn, 'fn', []], [:brace_op, '{']],
		"fn {" => [[:fn, 'fn', []], [:brace_op, '{']]
	}	
	# checks parse tree structure
	def test_basic_struct
		@@OPS_BASIC_STRUCT.each do |stmt, estruct|
			begin
				struct = EE.struct(stmt)
				assert_equal(estruct, struct, "structure fail: #{stmt}")
			rescue => ex
				assert(false, "exception for statement: #{stmt}: #{ex.message}\n\t#{ex.backtrace.join("\n\t")}")
			end
		end
	end

	# a set of basic logical and mathematical operations tested during test_basic_ops
	@@OPS_BASIC = {
		"1 + 1" => 2,
		"1 * 5" => 5,
		"1 + 5 * 3" => 16,
		"1 - 3 / 3" => 0,
		"6 * 2 + 5" => 17,
		"6 * (2 + 5)" => 42,
		"1 == 1" => true,
		"1 != 2" => true,
		"(6*3) > (2*5)" => true,
		"(6*3) < (2*5)" => false,
	}

	# go through basic evaluations as an overall sanity check
	def test_basic_ops
		$stderr.write "#{'-'*20} test_basic_ops #{'-'*20}\n"
		@@OPS_BASIC.each do |statement, expected|
			begin
				struct = EE.struct(statement)
				val = EE.expr_eval(struct, {}, {})
				assert_equal(expected, val, "unexpected results for: #{statement}")
			rescue => ex
				$stderr.write "struct=#{struct.inspect}\n"
				assert(false, "exception for statement: #{statement}: #{ex.message}\n\t#{ex.backtrace.join("\n\t")}")
			end
		end
	end

	@@OPS_BASIC_VARS = {
		"1 + ab" => [[:op, '+', 1, [:var, 'ab']]],
		"1 + ab[c]" => [[:op, '+', 1, [:var, 'ab[c]']]],
		"1 + (ab[c][0].func - 1)" => [[:op, '+', 1, [:op, '-', [:var, 'ab[c][0].func'], 1, :group]]]
	}

	def test_var_parsing
		@@OPS_BASIC_VARS.each do |statement, expected|
			begin
				struct = EE.struct(statement)
				assert_equal(expected, struct, "unexpected results for: #{statement}")
			rescue => ex
				assert(false, "exception for statement: #{statement}: #{ex.message}\n\t#{ex.backtrace.join("\n\t")}")
			end
		end
	end
	
	# test variable get/set
	@@OPS_VAR_GET = {
		'a' => 'a',
		'map' => {'a' => 1, 'b' => {'c' => {}, 'd' => 2}},
		'map[a]' => 1,
		"map['a']" => 1,
		'map["a"]' => 1,
		'map[a][b][d]' => nil,
		'map[b][d]' => nil,
		'map["b"][\'d\']' => 2
	}

	def test_var_get_set
		vtable = {'a' => 'a'}
		vtable['map'] = {'a' => 1, 'b' => {'c' => {}, 'd' => 2}}
		vtable['arr'] = []

		@@OPS_VAR_GET.each do |var, val|		
			begin
				rv = EE.retrieve_var(var, vtable, {}, false)
				assert_equal(val, rv, "get failed: #{var}")
			rescue => ex
				assert(false, "exception for retrieve_var: #{var}: #{ex.message}\n\t#{ex.backtrace.join("\n\t")}")
			end
		end
	end
	
	# for things like `func(..) {` (used when defining block macros)
	def test_terminal_frags
	end
end