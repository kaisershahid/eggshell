require 'test/unit/testcase'

class Eggshell_TestExprEval < Test::Unit::TestCase
	EE = Eggshell::ExpressionEvaluator
	
	def initialize(a1 = nil)
		super(a1)
		@vars = {}
		@funcs = {}
		@ee = EE.new(@vars, @funcs)
		
		@ee.register_function_whitelist(String, ['length'])
		@ee.register_function_whitelist(VarTest, ['some_getter'], ['some_setter'])
		@ee.register_function_alias(VarTest)
		
		@vars['map'] = {'key1' => 'val1', 'key2' => 'val2', 'vartest' => VarTest.new}
	end
	
	# a set of basic logical and mathematical operations tested during test_basic_ops
	@@OPS_BASIC = {
		"1 + 1" => 2,
		"1 * 5" => 5,
		"1 + 5 * 3" => 16,
		"1 - 3 / 3" => 0,
		"6 * 2 + 5" => 17,
		"6 * (2 + 5)" => 42,
		"6 * (2 + 5 * 2 - 1)" => 66,
		"6 * (2 + 5 * 2 - 1 + (10/2))" => 96,
		"1 == 1" => true,
		"1 === 1" => true,
		"1 === '1'" => false,
		"1 != 2" => true,
		"(6*3) > (2*5)" => true,
		"(6*3) < (2*5)" => false,
		"'' == empty" => true,
		"nil == empty" => true,
		"' ' != empty" => true,
		"('aa' =~ 'a') != empty" => true,
		"('aa' !=~ 'a') == empty" => true,
		"'ab' =~ 'c'" => nil
	}

	# go through basic evaluations as an overall sanity check
	def test_basic_ops
		$stderr.write "#{'-'*20} test_basic_ops #{'-'*20}\n"
		@@OPS_BASIC.each do |statement, expected|
			begin
				struct = @ee.parse(statement)
				val = @ee.evaluate(struct)
				assert_equal(expected, val, "unexpected results for: #{statement}")
			rescue => ex
				$stderr.write "struct=#{struct.inspect}\n"
				assert(false, "exception for statement: #{statement}: #{ex.message}\n\t#{ex.backtrace.join("\n\t")}")
			end
		end
	end
	
	def test_func_alias
		# $stderr.write "alias map:\n#{@ee.get_function_aliases.join("\n")}\n"
		assert_equal(true, @ee.has_function_alias(VarTest, 'length'), 'get: VarTest.length')
		assert_equal(true, @ee.has_function_alias(@vars['map']['vartest'], 'some_getter'), 'get: VarTest.some_getter')
		assert_equal(true, @ee.has_function_alias(@vars['map']['vartest'], 'some_setter', :set), 'set: VarTest.some_getter')
	end
	
	def test_var_get_set
		expr = "map['vartest'].some_setter"
		struct = @ee.parse(expr)
		@ee.var_access(struct[0], nil, "!!!")
		assert_equal('!!!', @vars['map']['vartest'].some_getter, "some_setter failed")
		assert_equal('!!!', @ee.var_access(@ee.parse("map['vartest'].some_getter")[0])[0], "some_getter failed")
	end
end

class VarTest < String
	def initialize()
		@var = 'default_var'
	end

	def some_getter()
		@var
	end
	
	def some_setter(val)
		@var = val
	end
end