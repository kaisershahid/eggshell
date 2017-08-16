
# line 1 "lexer.ragel"

# line 71 "lexer.ragel"

# %

module Eggshell; class ExpressionEvaluator
class Eggshell::ExpressionEvaluator::Lexer

	def initialize(parser)
		@parser = parser
		
# line 15 "lexer.rb"
class << self
	attr_accessor :_eggshell_actions
	private :_eggshell_actions, :_eggshell_actions=
end
self._eggshell_actions = [
	0, 1, 0, 1, 1, 1, 2, 1, 
	3, 1, 4, 1, 5, 1, 6, 1, 
	7, 1, 8, 1, 9, 1, 10, 1, 
	11, 1, 12, 1, 13, 1, 14, 1, 
	15, 1, 16, 1, 17, 1, 18, 1, 
	19
]

class << self
	attr_accessor :_eggshell_key_offsets
	private :_eggshell_key_offsets, :_eggshell_key_offsets=
end
self._eggshell_key_offsets = [
	0, 2, 38, 43, 44, 46, 49, 51, 
	52, 54, 55, 56, 58, 68
]

class << self
	attr_accessor :_eggshell_trans_keys
	private :_eggshell_trans_keys, :_eggshell_trans_keys=
end
self._eggshell_trans_keys = [
	48, 57, 13, 32, 34, 36, 38, 39, 
	43, 44, 45, 46, 58, 59, 60, 61, 
	62, 63, 64, 91, 92, 93, 94, 124, 
	9, 10, 40, 41, 42, 47, 48, 57, 
	65, 95, 97, 122, 123, 125, 95, 65, 
	90, 97, 122, 38, 48, 57, 46, 48, 
	57, 48, 57, 58, 60, 61, 61, 61, 
	61, 62, 34, 91, 93, 110, 114, 116, 
	123, 125, 39, 41, 124, 0
]

class << self
	attr_accessor :_eggshell_single_lengths
	private :_eggshell_single_lengths, :_eggshell_single_lengths=
end
self._eggshell_single_lengths = [
	0, 22, 1, 1, 0, 1, 0, 1, 
	0, 1, 1, 0, 8, 1
]

class << self
	attr_accessor :_eggshell_range_lengths
	private :_eggshell_range_lengths, :_eggshell_range_lengths=
end
self._eggshell_range_lengths = [
	1, 7, 2, 0, 1, 1, 1, 0, 
	1, 0, 0, 1, 1, 0
]

class << self
	attr_accessor :_eggshell_index_offsets
	private :_eggshell_index_offsets, :_eggshell_index_offsets=
end
self._eggshell_index_offsets = [
	0, 2, 32, 36, 38, 40, 43, 45, 
	47, 49, 51, 53, 55, 65
]

class << self
	attr_accessor :_eggshell_indicies
	private :_eggshell_indicies, :_eggshell_indicies=
end
self._eggshell_indicies = [
	1, 0, 3, 3, 4, 5, 6, 4, 
	9, 10, 9, 10, 12, 10, 13, 14, 
	15, 8, 16, 17, 18, 17, 8, 20, 
	3, 7, 8, 11, 5, 5, 19, 2, 
	5, 5, 5, 21, 8, 22, 11, 23, 
	25, 11, 24, 1, 26, 16, 27, 8, 
	23, 28, 23, 8, 23, 8, 23, 29, 
	29, 29, 29, 29, 29, 29, 29, 29, 
	22, 8, 22, 0
]

class << self
	attr_accessor :_eggshell_trans_targs
	private :_eggshell_trans_targs, :_eggshell_trans_targs=
end
self._eggshell_trans_targs = [
	1, 6, 1, 1, 1, 2, 3, 1, 
	1, 4, 1, 5, 7, 8, 9, 11, 
	1, 1, 12, 1, 13, 1, 1, 1, 
	1, 0, 1, 1, 10, 1
]

class << self
	attr_accessor :_eggshell_trans_actions
	private :_eggshell_trans_actions, :_eggshell_trans_actions=
end
self._eggshell_trans_actions = [
	39, 0, 25, 23, 15, 0, 0, 13, 
	7, 0, 19, 5, 0, 0, 0, 0, 
	17, 9, 0, 11, 0, 31, 37, 33, 
	27, 0, 29, 35, 0, 21
]

class << self
	attr_accessor :_eggshell_to_state_actions
	private :_eggshell_to_state_actions, :_eggshell_to_state_actions=
end
self._eggshell_to_state_actions = [
	0, 1, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0
]

class << self
	attr_accessor :_eggshell_from_state_actions
	private :_eggshell_from_state_actions, :_eggshell_from_state_actions=
end
self._eggshell_from_state_actions = [
	0, 3, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0
]

class << self
	attr_accessor :_eggshell_eof_trans
	private :_eggshell_eof_trans, :_eggshell_eof_trans=
end
self._eggshell_eof_trans = [
	1, 0, 22, 23, 24, 25, 27, 28, 
	24, 24, 24, 24, 23, 23
]

class << self
	attr_accessor :eggshell_start
end
self.eggshell_start = 1;
class << self
	attr_accessor :eggshell_first_final
end
self.eggshell_first_final = 1;
class << self
	attr_accessor :eggshell_error
end
self.eggshell_error = -1;

class << self
	attr_accessor :eggshell_en_main
end
self.eggshell_en_main = 1;


# line 80 "lexer.ragel"
		# %
	end
	
	def process(source)
		data = source.is_a?(String) ? source.unpack("c*") : source
		eof = data.length
		
# line 173 "lexer.rb"
begin
	p ||= 0
	pe ||= data.length
	cs = eggshell_start
	ts = nil
	te = nil
	act = 0
end

# line 87 "lexer.ragel"
		
# line 185 "lexer.rb"
begin
	_klen, _trans, _keys, _acts, _nacts = nil
	_goto_level = 0
	_resume = 10
	_eof_trans = 15
	_again = 20
	_test_eof = 30
	_out = 40
	while true
	_trigger_goto = false
	if _goto_level <= 0
	if p == pe
		_goto_level = _test_eof
		next
	end
	end
	if _goto_level <= _resume
	_acts = _eggshell_from_state_actions[cs]
	_nacts = _eggshell_actions[_acts]
	_acts += 1
	while _nacts > 0
		_nacts -= 1
		_acts += 1
		case _eggshell_actions[_acts - 1]
			when 1 then
# line 1 "NONE"
		begin
ts = p
		end
# line 215 "lexer.rb"
		end # from state action switch
	end
	if _trigger_goto
		next
	end
	_keys = _eggshell_key_offsets[cs]
	_trans = _eggshell_index_offsets[cs]
	_klen = _eggshell_single_lengths[cs]
	_break_match = false
	
	begin
	  if _klen > 0
	     _lower = _keys
	     _upper = _keys + _klen - 1

	     loop do
	        break if _upper < _lower
	        _mid = _lower + ( (_upper - _lower) >> 1 )

	        if data[p].ord < _eggshell_trans_keys[_mid]
	           _upper = _mid - 1
	        elsif data[p].ord > _eggshell_trans_keys[_mid]
	           _lower = _mid + 1
	        else
	           _trans += (_mid - _keys)
	           _break_match = true
	           break
	        end
	     end # loop
	     break if _break_match
	     _keys += _klen
	     _trans += _klen
	  end
	  _klen = _eggshell_range_lengths[cs]
	  if _klen > 0
	     _lower = _keys
	     _upper = _keys + (_klen << 1) - 2
	     loop do
	        break if _upper < _lower
	        _mid = _lower + (((_upper-_lower) >> 1) & ~1)
	        if data[p].ord < _eggshell_trans_keys[_mid]
	          _upper = _mid - 2
	        elsif data[p].ord > _eggshell_trans_keys[_mid+1]
	          _lower = _mid + 2
	        else
	          _trans += ((_mid - _keys) >> 1)
	          _break_match = true
	          break
	        end
	     end # loop
	     break if _break_match
	     _trans += _klen
	  end
	end while false
	_trans = _eggshell_indicies[_trans]
	end
	if _goto_level <= _eof_trans
	cs = _eggshell_trans_targs[_trans]
	if _eggshell_trans_actions[_trans] != 0
		_acts = _eggshell_trans_actions[_trans]
		_nacts = _eggshell_actions[_acts]
		_acts += 1
		while _nacts > 0
			_nacts -= 1
			_acts += 1
			case _eggshell_actions[_acts - 1]
when 2 then
# line 1 "NONE"
		begin
te = p+1
		end
when 3 then
# line 31 "lexer.ragel"
		begin
te = p+1
 begin 
			@parser.emit(:logical_op, data, ts, te)
		 end
		end
when 4 then
# line 35 "lexer.ragel"
		begin
te = p+1
 begin 
			@parser.emit(:index_group, data, ts, te);
		 end
		end
when 5 then
# line 39 "lexer.ragel"
		begin
te = p+1
 begin 
			@parser.emit(:brace_group, data, ts, te);
		 end
		end
when 6 then
# line 43 "lexer.ragel"
		begin
te = p+1
 begin 
			@parser.emit(:paren_group, data, ts, te);
		 end
		end
when 7 then
# line 47 "lexer.ragel"
		begin
te = p+1
 begin 
			@parser.emit(:str_delim, data, ts, te);
		 end
		end
when 8 then
# line 51 "lexer.ragel"
		begin
te = p+1
 begin 
			@parser.emit(:modifier, data, ts, te);
		 end
		end
when 9 then
# line 55 "lexer.ragel"
		begin
te = p+1
 begin 
			@parser.emit(:separator, data, ts, te);
		 end
		end
when 10 then
# line 59 "lexer.ragel"
		begin
te = p+1
 begin 
			@parser.emit(:escape, data, ts, te);
		 end
		end
when 11 then
# line 63 "lexer.ragel"
		begin
te = p+1
 begin 
			@parser.emit(:space, data, ts, te)
		 end
		end
when 12 then
# line 67 "lexer.ragel"
		begin
te = p+1
 begin 
			@parser.emit(:string, data, ts, te)
		 end
		end
when 13 then
# line 19 "lexer.ragel"
		begin
te = p
p = p - 1; begin  
			@parser.emit(:number_literal, data, ts, te) 
		 end
		end
when 14 then
# line 23 "lexer.ragel"
		begin
te = p
p = p - 1; begin  
			@parser.emit(:number_literal, data, ts, te) 
		 end
		end
when 15 then
# line 27 "lexer.ragel"
		begin
te = p
p = p - 1; begin  
			@parser.emit(:identifier, data, ts, te) 
		 end
		end
when 16 then
# line 31 "lexer.ragel"
		begin
te = p
p = p - 1; begin 
			@parser.emit(:logical_op, data, ts, te)
		 end
		end
when 17 then
# line 51 "lexer.ragel"
		begin
te = p
p = p - 1; begin 
			@parser.emit(:modifier, data, ts, te);
		 end
		end
when 18 then
# line 67 "lexer.ragel"
		begin
te = p
p = p - 1; begin 
			@parser.emit(:string, data, ts, te)
		 end
		end
when 19 then
# line 19 "lexer.ragel"
		begin
 begin p = ((te))-1; end
 begin  
			@parser.emit(:number_literal, data, ts, te) 
		 end
		end
# line 423 "lexer.rb"
			end # action switch
		end
	end
	if _trigger_goto
		next
	end
	end
	if _goto_level <= _again
	_acts = _eggshell_to_state_actions[cs]
	_nacts = _eggshell_actions[_acts]
	_acts += 1
	while _nacts > 0
		_nacts -= 1
		_acts += 1
		case _eggshell_actions[_acts - 1]
when 0 then
# line 1 "NONE"
		begin
ts = nil;		end
# line 443 "lexer.rb"
		end # to state action switch
	end
	if _trigger_goto
		next
	end
	p += 1
	if p != pe
		_goto_level = _resume
		next
	end
	end
	if _goto_level <= _test_eof
	if p == eof
	if _eggshell_eof_trans[cs] > 0
		_trans = _eggshell_eof_trans[cs] - 1;
		_goto_level = _eof_trans
		next;
	end
end
	end
	if _goto_level <= _out
		break
	end
	end
	end

# line 88 "lexer.ragel"
		# %
	end
end
end; end