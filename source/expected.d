/++
This module is implementing the Expected idiom.

See the (Andrei Alexandrescu’s talk (Systematic Error Handling in C++)[http://channel9.msdn.com/Shows/Going+Deep/C-and-Beyond-2012-Andrei-Alexandrescu-Systematic-Error-Handling-in-C]
and (its slides)[https://skydrive.live.com/?cid=f1b8ff18a2aec5c5&id=F1B8FF18A2AEC5C5!1158].

Or more recent ["Expect the Expected"](https://www.youtube.com/watch?v=nVzgkepAg5Y) by Andrei Alexandrescu for further background.

It is also inspired by C++'s proposed [std::expected](https://wg21.link/p0323).

Similar work is (expectations)[http://code.dlang.org/packages/expectations] by Paul Backus.

Main differences with that are:

* lightweight, no other external dependencies
* allows to use same types for `T` and `E`
* allows to define `Expected` without value (`void` for `T`)
* provides facility to change the `Expected` behavior by custom `Hook` implementation using the Design by introspection.

Default type for error is `string`, i.e. `Expected!int` is the same as `Expected!(int, string)`

`Expected` has customizable behavior with the help of a third type parameter,
`Hook`. Depending on what methods `Hook` defines, core operations on the
`Expected` may be verified or completely redefined.
If `Hook` defines no method at all and carries no state, there is no change in
default behavior.
This module provides a few predefined hooks (below) that add useful behavior to
`Expected`:

$(BOOKTABLE ,
    $(TR $(TD $(LREF Abort)) $(TD
        fails every incorrect operation with a call to `assert(0)`.
		It is the default third parameter, i.e. `Expected!short` is the same as
        $(D Expected!(short, string, Abort)).
    ))
    $(TR $(TD $(LREF Throw)) $(TD
        fails every incorrect operation by throwing an exception.
    ))
)

The hook's members are looked up statically in a Design by Introspection manner
and are all optional. The table below illustrates the members that a hook type
may define and their influence over the behavior of the `Checked` type using it.
In the table, `hook` is an alias for `Hook` if the type `Hook` does not
introduce any state, or an object of type `Hook` otherwise.

$(TABLE ,
    $(TR $(TH `Hook` member) $(TH Semantics in $(D Expected!(T, E, Hook)))
    )
    $(TR $(TD `enableDefaultConstructor`) $(TD If defined, `Expected` would have
    enabled or disabled default constructor based on it's `bool` value. Default
    constructor is disabled by default.

    `Expected` would have generated `opAssign` for value and error types,
    if default constructor is enabled)
    )
    $(TR $(TD `onAccessEmptyValue`) $(TD If value is accessed on unitialized
    `Expected` or `Expected` with error value, $(D hook.onAccessEmptyValue!E(err))
    is called.

    If hook doesn't implement the handler, `T.init` is returned.)
    )
    $(TR $(TD `onAccessEmptyError`) $(TD If error is accessed on unitialized
    `Expected` or `Expected` with value, $(D hook.onAccessEmptyError())
    is called.

    If hook doesn't implement the handler, `E.init` is returned.)
    )
)

License: BSL-1.0
Author: Tomáš Chaloupka
+/

//TODO: collect errno function call - see https://dlang.org/phobos/std_exception.html#ErrnoException
//TODO: documentation and usage examples
//TODO: ability to enforce error handling (via refcounted payload)

module expected;

version (unittest) import std.exception : assertThrown;

@safe:

/++
	`Expected!(T, E)` is a type that represents either success or failure.

	Type `T` is used for success value.
	If `T` is `void`, then `Expected` can only hold error value and is considered a success when there is no error value.

	Type `E` is used for error value.
	The default type for the error value is `string`.

	Default behavior of `Expected` can be modified by the `Hook` template parameter.

	Params:
		T    = represents the expected value
		E    = represents the reason explaining why it doesn’t contains avalue of type T, that is the unexpected value.
		Hook = defines the `Expected` type behavior
+/
struct Expected(T, E = string, Hook = Abort)
	if (!is(E == void))
{
	import std.functional: forward;
	import std.meta : AliasSeq, Erase, NoDuplicates;
	import std.traits: isAssignable, isCopyable, Unqual;
	import std.typecons : Flag, No, Yes;

	private alias Types = NoDuplicates!(Erase!(void, AliasSeq!(T, E)));

	static foreach (i, T; Types)
	{
		/++
			Constructs an `Expected` with value or error based on the tye of the provided.

			In case when `T == E`, it constructs `Expected` with value.

			In case when `T == void`, it constructs `Expected` with error value.

			Default constructor (if enabled) initializes `Expected` to `T.init` value.
			If `T == void`, it initializes `Expected` with no error.
		+/
		this()(auto ref T val)
		{
			static if (isCopyable!T) storage = Storage(val);
			else storage = Storage(forward!val);
			setState!(T, Yes.force)();
		}

		static if (isCopyable!T)
		{
			/// ditto
			this()(auto ref const(T) val) const
			{
				storage = const(Storage)(val);
				setState!(T, Yes.force)();
			}

			/// ditto
			this()(auto ref immutable(T) val) immutable
			{
				storage = immutable(Storage)(val);
				setState!(T, Yes.force)();
			}
		}
		else
		{
			@disable this(const(T) val) const;
			@disable this(immutable(T) val) immutable;
		}
	}

	// generate constructor with flag to determine type of value
	static if (Types.length == 1 && !is(T == void))
	{
		/++ Constructs an `Expected` with value or error based on the provided flag.
			This constructor is available only for cases when value and error has the same type,
			so we can still construct `Expected` with value or error.

			Params:
				val     = Value to set as value or error
				success = If `true`, `Expected` with value is created, `Expected` with error otherwise.
		+/
		this()(auto ref E val, bool success)
		{
			static if (isCopyable!T) storage = Storage(val);
			else storage = Storage(forward!val);
			setState!E(success ? State.value : State.error);
		}

		static if (isCopyable!E)
		{
			/// ditto
			this()(auto ref const(E) val, bool success) const
			{
				storage = const(Storage)(val);
				setState!E(success ? State.value : State.error);
			}

			/// ditto
			this()(auto ref immutable(E) val, bool success) immutable
			{
				storage = immutable(Storage)(val);
				setState!E(success ? State.value : State.error);
			}
		}
		else
		{
			@disable this(const(E) val, bool success) const;
			@disable this(immutable(E) val, bool success) immutable;
		}
	}

	static if (!is(T == void) && !isDefaultConstructorEnabled!Hook) @disable this();

	static if (isDefaultConstructorEnabled!Hook)
	{
		static foreach (i, CT; Types)
		{
			static if (isAssignable!CT)
			{
				/++ Assigns a value or error to an `Expected`.

					Note: This is only allowed when default constructor is also enabled.
				+/
				void opAssign()(auto ref CT rhs)
				{
					//TODO: Hook to disallow reassign
					storage = Storage(forward!rhs);
					setState!CT();
				}
			}
		}
	}

	/++ Implicit conversion to bool.
		Returns: `true` if there is no error set, `false` otherwise.
	+/
	bool opCast(T)() const if (is(T == bool)) { return !this.hasError; }

	static if (!is(T == void))
	{
		/++ Checks whether this `Expected` object contains a specific expected value.

			* `opEquals` for the value is available only when `T != void`.
			* `opEquals` for the error isn't available, use equality test for `Expected` in that case.
		+/
		bool opEquals()(const auto ref T rhs) const
		{
			return hasValue && value == rhs;
		}
	}

	/// Checks whether this `Expected` object and `rhs` contain the same expected value or error value.
	bool opEquals()(const auto ref Expected!(T, E, Hook) rhs) const
	{
		if (state != rhs.state) return false;
		static if (!is(T == void)) { if (hasValue) return value == rhs.value; }
		return error == rhs.error;
	}

	/++ Calculates the hash value of the `Expected` in a way that iff it has a value,
		it returns hash of the value.
		Hash is computed using internal state and storage of the `Expected` otherwise.
	+/
	size_t toHash()() const nothrow
	{
		static if (!is(T == void)) { if (hasValue) return value.hashOf; }
		return storage.hashOf(state);
	}

	static if (!is(T == void))
	{
		/// Checks if `Expected` has value
		@property bool hasValue()() const { return state == State.value; }

		/++
			Returns the expected value if there is one.

			With default `Abort` hook, it asserts when there is no value.
			It calls hook's `onAccessEmptyValue` otherwise.

			It returns `T.init` when hook doesn't provide `onAccessEmptyValue`.
		+/
		@property auto ref inout(T) value() inout
		{
			if (state != State.value)
			{
				static if (hasOnAccessEmptyValue!(Hook, E))
					__traits(getMember, Hook, "onAccessEmptyValue")(state == State.error ? trustedGetError() : E.init);
				else return T.init;
			}
			return trustedGetValue();
		}
	}

	/// Checks if `Expected` has error
	@property bool hasError()() const { return state == State.error; }

	/++
		Returns the error value. May only be called when `hasValue` returns `false`.

		If there is no error value, it calls hook's `onAccessEmptyError`.

		It returns `E.init` when hook doesn't provide `onAccessEmptyError`.
	+/
	@property auto ref inout(E) error() inout
	{
		if (state != State.error)
		{
			static if (hasOnAccessEmptyError!Hook) __traits(getMember, Hook, "onAccessEmptyError")();
			else return E.init;
		}
		return trustedGetError;
	}

	// range interface
	static if (!is(T == void))
	{
		/++ Range interface defined by `empty`, `front`, `popFront`.
			Yields one value if `Expected` has value.

			If `T == void`, range interface isn't defined.
		+/
		@property bool empty() const { return state != State.value; }

		/// ditto
		@property auto ref inout(T) front() inout { return value; }

		/// ditto
		void popFront() { state = State.empty; }
	}

	private:

	//FIXME: can probably be union instead, but that doesn't work well with destructors and copy constructors/postblits
	//or change it for a couple of pointers and make the Expected payload refcounted
	//that could be used to enforce result check too
	struct Storage
	{
		Types values;

		// generate storage constructors
		static foreach (i, CT; Types)
		{
			@trusted this()(auto ref CT val)
			{
				static if (isCopyable!CT) __traits(getMember, Storage, "values")[i] = val;
				else __traits(getMember, Storage, "values")[i] = forward!val;
			}

			static if (isCopyable!CT)
			{
				@trusted this()(auto ref const(CT) val) const { __traits(getMember, Storage, "values")[i] = val; }
				@trusted this()(auto ref immutable(CT) val) immutable { __traits(getMember, Storage, "values")[i] = val; }
			}
			else
			{
				@disable this(const(CT) val) const;
				@disable this(immutable(CT) val) immutable;
			}
		}
	}

	//@trusted // needed for union
	ref inout(E) trustedGetError()() inout
	{
		static if (Types.length == 1) return __traits(getMember, storage, "values")[0];
		else return __traits(getMember, storage, "values")[1];
	}

	static if (!is(T == void))
	{
		//@trusted // needed for union
		ref inout(T) trustedGetValue()() inout
		{
			return __traits(getMember, storage, "values")[0];
		}
	}

	enum State : ubyte { empty, value, error }

	Storage storage;
	State state = State.empty;

	void setState(MT, Flag!"force" force = No.force)()
	{
		State s;
		static if (Types.length == 1 && is(T == void)) s = State.error;
		else static if (Types.length == 1 || is(MT == T)) s = State.value;
		else s = State.error;

		static if (!force)
		{
			//TODO: change with Hook?
			assert(state == State.empty || state == s, "Can't change meaning of already set Expected type");
		}

		state = s;
	}
}

/// Template to determine if provided Hook enables default constructor for `Expected`
template isDefaultConstructorEnabled(Hook)
{
	static if (__traits(hasMember, Hook, "enableDefaultConstructor"))
	{
		static assert(
			is(typeof(__traits(getMember, Hook, "enableDefaultConstructor")) : bool),
			"Hook's enableDefaultConstructor is expected to be of type bool"
		);
		static if (__traits(getMember, Hook, "enableDefaultConstructor")) enum isDefaultConstructorEnabled = true;
		else enum isDefaultConstructorEnabled = false;
	}
	else enum isDefaultConstructorEnabled = false;
}

///
unittest
{
	struct Foo {}
	struct Bar { static immutable bool enableDefaultConstructor = true; }
	static assert(!isDefaultConstructorEnabled!Foo);
	static assert(isDefaultConstructorEnabled!Bar);
}

/++ Template to determine if hook provides function called on empty value.
+/
template hasOnAccessEmptyValue(Hook, E)
{
	static if (__traits(hasMember, Hook, "onAccessEmptyValue"))
	{
		static assert(
			is(typeof(__traits(getMember, Hook, "onAccessEmptyValue")(E.init))),
			"Hook's onAccessEmptyValue is expected to be callable with error value type"
		);
		enum hasOnAccessEmptyValue = true;
	}
	else enum hasOnAccessEmptyValue = false;
}

///
unittest
{
	struct Foo {}
	struct Bar { static void onAccessEmptyValue(E)(E err) {} }
	static assert(!hasOnAccessEmptyValue!(Foo, string));
	static assert(hasOnAccessEmptyValue!(Bar, string));
}

/++ Template to determine if hook provides function called on empty error.
+/
template hasOnAccessEmptyError(Hook)
{
	static if (__traits(hasMember, Hook, "onAccessEmptyError"))
	{
		static assert(
			is(typeof(__traits(getMember, Hook, "onAccessEmptyError")())),
			"Hook's onAccessEmptyValue is expected to be callable with no arguments"
		);
		enum hasOnAccessEmptyError = true;
	}
	else enum hasOnAccessEmptyError = false;
}

///
unittest
{
	struct Foo {}
	struct Bar { static void onAccessEmptyError() {} }
	static assert(!hasOnAccessEmptyError!Foo);
	static assert(hasOnAccessEmptyError!Bar);
}

/++ Default hook implementation for `Expected`
+/
struct Abort
{
static:
	/++ Default constructor for `Expected` is disabled
		Same with the `opAssign`, so `Expected` can be only constructed
		once and not modified afterwards.
	+/
	immutable bool enableDefaultConstructor = false;

	/// Handler for case when empty value is accessed
	void onAccessEmptyValue(E)(E err) nothrow @nogc
	{
		assert(0, "Can't access value of unexpected");
	}

	/// Handler for case when empty error is accessed
	void onAccessEmptyError() nothrow @nogc
	{
		assert(0, "Can't access error on expected value");
	}
}

@system unittest
{
	static assert(!isDefaultConstructorEnabled!Abort);
	static assert(hasOnAccessEmptyValue!(Abort, string));
	static assert(hasOnAccessEmptyValue!(Abort, int));
	static assert(hasOnAccessEmptyError!Abort);

	assertThrown!Throwable(expected(42).error);
	assertThrown!Throwable(unexpected!int("foo").value);
}

/++ Hook implementation that throws exceptions instead of default assert behavior.
+/
struct Throw
{
static:

	/++ Default constructor for `Expected` is disabled
		Same with the `opAssign`, so `Expected` can be only constructed
		once and not modified afterwards.
	+/
	immutable bool enableDefaultConstructor = false;

	/++ Handler for case when empty value is accessed

		Throws:
			If `E` inherits from `Throwable`, the error value is thrown.
			Otherwise, an [Unexpected] instance containing the error value is
			thrown.
	+/
	void onAccessEmptyValue(E)(E err)
	{
		static if(is(E : Throwable)) throw err;
		else throw new Unexpected!E(err);
	}

	/// Handler for case when empty error is accessed
	void onAccessEmptyError()
	{
		throw new Unexpected!string("Can't access error on expected value");
	}
}

unittest
{
	static assert(!isDefaultConstructorEnabled!Throw);
	static assert(hasOnAccessEmptyValue!(Throw, string));
	static assert(hasOnAccessEmptyValue!(Throw, int));
	static assert(hasOnAccessEmptyError!Throw);

	assertThrown!(Unexpected!string)(expected!(string, Throw)(42).error);
	assertThrown!(Unexpected!string)(unexpected!(int, Throw)("foo").value);
}

/// An exception that represents an error value.
class Unexpected(T) : Exception
{
	T error; /// error value

	/// Constructs an `Unexpected` exception from an error value.
	pure @safe @nogc nothrow
	this(T value, string file = __FILE__, size_t line = __LINE__)
	{
		super("Unexpected error", file, line);
		this.error = error;
	}
}

/++
	Creates an `Expected` object from an expected value, with type inference.
+/
Expected!(T, E, Hook) expected(E = string, Hook = Abort, T)(T value)
{
	return Expected!(T, E, Hook)(value);
}

/// ditto
Expected!(void, E, Hook) expected(E = string, Hook = Abort)()
{
	return Expected!(void, E, Hook)();
}

// expected
unittest
{
	// void
	{
		auto res = expected();
		static assert(is(typeof(res) == Expected!(void, string)));
		assert(res);
	}

	// int
	{
		auto res = expected(42);
		static assert(is(typeof(res) == Expected!(int, string)));
		assert(res);
		assert(res.value == 42);
	}

	// string
	{
		auto res = expected("42");
		static assert(is(typeof(res) == Expected!(string, string)));
		assert(res);
		assert(res.value == "42");
	}

	// other error type
	{
		auto res = expected!bool(42);
		static assert(is(typeof(res) == Expected!(int, bool)));
		assert(res);
		assert(res.value == 42);
	}
}

/++ Constructs `Expected` from the result of the provided function.

	If the function is `nothrow`, it just returns it's result using `expected`.

	If not, then it uses `try catch` block and constructs `Expected` with value or error.
+/
template expected(alias fun, Hook = Abort)
{
	auto expected(Args...)(auto ref Args args) if (is(typeof(fun(args))))
	{
		import std.traits : hasFunctionAttributes;

		alias T = typeof(fun(args));
		static if (is(hasFunctionAttributes!(fun, "nothrow"))) return expected!Exception(fun(args));
		else
		{
			try return Expected!(T, Exception)(fun(args));
			catch (Exception ex) return unexpected!T(ex);
		}
	}
}

///
unittest
{
	auto fn(int v) { if (v == 42) throw new Exception("don't panic"); return v; }

	assert(expected!fn(1) == 1);
	assert(expected!fn(42).error.msg == "don't panic");
}

/++
	Creates an `Expected` object from an error value, with type inference.
+/
Expected!(T, E, Hook) unexpected(T = void, Hook = Abort, E)(E err)
{
	static if (Expected!(T, E, Hook).Types.length == 1 && !is(T == void))
		return Expected!(T, E, Hook)(err, false);
	else return Expected!(T, E, Hook)(err);
}

//unexpected
unittest
{
	// implicit void value type
	{
		auto res = unexpected("foo");
		static assert(is(typeof(res) == Expected!(void, string)));
		assert(!res);
		assert(res.error == "foo");
	}

	// bool
	{
		auto res = unexpected!int("42");
		static assert(is(typeof(res) == Expected!(int, string)));
		assert(!res);
		assert(res.error == "42");
	}

	// other error type
	{
		auto res = unexpected!bool(42);
		static assert(is(typeof(res) == Expected!(bool, int)));
		assert(!res);
		assert(res.error == 42);
	}
}

/++
	Returns the error contained within the `Expected` _and then_ another value if there's no error.
	This function can be used for control flow based on `Expected` values.

	Params:
		exp = The `Expected` to call andThen on
		value = The value to return if there isn't an error
		pred = The predicate to call if the there isn't an error
+/
auto ref EX andThen(EX)(auto ref EX exp, lazy EX value)
	if (is(EX : Expected!(T, E, H), T, E, H))
{
	return exp.andThen!value;
}

/// ditto
auto ref EX andThen(alias pred, EX)(auto ref EX exp)
	if (
		is(EX : Expected!(T, E, H), T, E, H)
		&& is(typeof(pred()) : EX)
	)
{
	return exp.hasError ? exp : pred();
}

///
unittest
{
	assert(expected(42).andThen(expected(1)) == 1);
	assert(expected(42).andThen!(() => expected(0)) == 0);
	assert(expected(42).andThen(unexpected!int("foo")).error == "foo");
	assert(expected(42).andThen!(() => unexpected!int("foo")).error == "foo");
	assert(unexpected!int("foo").andThen(expected(42)).error == "foo");
	assert(unexpected!int("foo").andThen!(() => expected(42)).error == "foo");
	assert(unexpected!int("foo").andThen(unexpected!int("bar")).error == "foo");
	assert(unexpected!int("foo").andThen!(() => unexpected!int("bar")).error == "foo");

	// with void value
	assert(expected().andThen!(() => expected()));
	assert(expected().andThen!(() => unexpected("foo")).error == "foo");
	assert(unexpected("foo").andThen!(() => expected()).error == "foo");
}

/++
	Returns the value contained within the `Expected` _or else_ another value if there's an error.
	This function can be used for control flow based on `Expected` values.

	Params:
		exp = The `Expected` to call orElse on
		value = The value to return if there is an error
		pred = The predicate to call if the there is an error
+/
U orElse(EX, U)(auto ref EX exp, lazy U value)
	if (is(EX : Expected!(T, E, H), T, E, H) && is(U : T))
{
	return exp.orElse!value;
}

/// ditto
auto ref orElse(alias pred, EX)(auto ref EX exp)
	if (is(EX : Expected!(T, E, H), T, E, H) && is(typeof(pred()) : T))
{
	return exp.hasError ? pred() : exp.value;
}

/// ditto
auto ref orElse(alias pred, EX)(auto ref EX exp)
	if (
		is(EX : Expected!(T, E, H), T, E, H)
		&& is(typeof(pred()) : Expected!(T, E, H))
	)
{
	return exp.hasError ? pred() : exp;
}

///
unittest
{
	assert(expected(42).orElse(0) == 42);
	assert(expected(42).orElse!(() => 0) == 42);
	assert(unexpected!int("foo").orElse(0) == 0);
	assert(unexpected!int("foo").orElse!(() => 0) == 0);
	assert(expected(42).orElse!(() => expected(0)) == 42);
	assert(unexpected!int("foo").orElse!(() => expected(42)) == 42);
	assert(unexpected!int("foo").orElse!(() => unexpected!int("bar")).error == "bar");

	// with void value
	assert(expected().orElse!(() => unexpected("foo")));
	assert(unexpected("foo").orElse!(() => expected()));
	assert(unexpected("foo").orElse!(() => unexpected("bar")).error == "bar");
}

/++
	Applies a function to the expected value in an `Expected` object.

	If no expected value is present, the original error value is passed through
	unchanged, and the function is not called.

	Params:
		op = function called to map `Expected` value
		hook = use another hook for mapped `Expected`

	Returns:
		A new `Expected` object containing the result.
+/
template map(alias op, Hook = Abort)
{
	/++
		The actual `map` function.

		Params:
			self = an [Expected] object
	+/
	auto map(T, E, H)(auto ref Expected!(T, E, H) self)
		if ((is(T == void) && is(typeof(op()))) || (!is(T == void) && is(typeof(op(self.value)))))
	{
		static if (is(T == void)) alias U = typeof(op());
		else alias U = typeof(op(self.value));

		if (self.hasError) return unexpected!(U, Hook)(self.error);
		else
		{
			static if (is(T == void)) return expected!(E, Hook)(op());
			else return expected!(E, Hook)(op(self.value));
		}
	}
}

///
unittest
{
	{
		assert(expected(42).map!((a) => a/2).value == 21);
		assert(expected().map!(() => 42).value == 42);
		assert(unexpected!int("foo").map!((a) => 42).error == "foo");
		assert(unexpected("foo").map!(() => 42).error == "foo");
	}

	// remap hook
	{
		static struct Hook {}
		auto res = expected(42).map!((a) => a/2, Hook);
		assert(res == 21);
		static assert(is(typeof(res) == Expected!(int, string, Hook)));
	}
}

/++
	Applies a function to the expected error in an `Expected` object.

	If no error is present, the original value is passed through
	unchanged, and the function is not called.

	Params:
		op = function called to map `Expected` error
		hook = use another hook for mapped `Expected`

	Returns:
		A new `Expected` object containing the result.
+/
template mapError(alias op, Hook = Abort)
{
	/++
		The actual `mapError` function.

		Params:
			self = an [Expected] object
	+/
	auto mapError(T, E, H)(auto ref Expected!(T, E, H) self)
		if (is(typeof(op(self.error))))
	{
		alias U = typeof(op(self.error));

		static if (!is(T == void))
		{
			if (self.hasValue) return expected!(U, Hook)(self.value);
		}
		return unexpected!(T, Hook)(op(self.error));
	}
}

///
unittest
{
	{
		assert(expected(42).mapError!((e) => e).value == 42);
		assert(unexpected("foo").mapError!((e) => 42).error == 42);
		assert(unexpected("foo").mapError!((e) => new Exception(e)).error.msg == "foo");
	}

	// remap hook
	{
		static struct Hook {}
		auto res = expected(42).mapError!((e) => e, Hook);
		assert(res == 42);
		static assert(is(typeof(res) == Expected!(int, string, Hook)));

		auto res2 = unexpected!int("foo").mapError!((e) => "bar", Hook);
		assert(res2.error == "bar");
		static assert(is(typeof(res2) == Expected!(int, string, Hook)));
	}
}

/++
	Maps a `Expected<T, E>` to `U` by applying a function to a contained value, or a fallback function to a contained error value.

	Both functions has to be of the same return type.

	This function can be used to unpack a successful result while handling an error.

	Params:
		valueOp = function called to map `Expected` value
		errorOp = function called to map `Expected` error
		hook = use another hook for mapped `Expected`

	Returns:
		A new `Expected` object containing the result.
+/
template mapOrElse(alias valueOp, alias errorOp)
{
	/++
		The actual `mapOrElse` function.

		Params:
			self = an [Expected] object
	+/
	auto mapOrElse(T, E, H)(auto ref Expected!(T, E, H) self)
		if (
			is(typeof(errorOp(self.error))) &&
			(
				(is(T == void) && is(typeof(valueOp()) == typeof(errorOp(self.error)))) ||
				(!is(T == void) && is(typeof(valueOp(self.value)) == typeof(errorOp(self.error))))
			)
		)
	{
		alias U = typeof(errorOp(self.error));

		if (self.hasError) return errorOp(self.error);
		else
		{
			static if (is(T == void)) return valueOp();
			else return valueOp(self.value);
		}
	}
}

unittest
{
	assert(expected(42).mapOrElse!((v) => v/2, (e) => 0) == 21);
	assert(expected().mapOrElse!(() => true, (e) => false));
	assert(unexpected!int("foo").mapOrElse!((v) => v/2, (e) => 42) == 42);
	assert(!unexpected("foo").mapOrElse!(() => true, (e) => false));
}

// -- global tests --

// Expected.init
@system nothrow unittest
{
	struct EnableDefaultConstructor { static immutable bool enableDefaultConstructor = true; }

	{
		auto res = Expected!(int, string).init;
		assert(!res.hasValue && !res.hasError);
		assert(res);
		assertThrown!Throwable(res.value);
		assertThrown!Throwable(res.error);
		static assert(!__traits(compiles, res = 42));
	}

	{
		auto res = Expected!(int, string, EnableDefaultConstructor).init;
		assert(!res.hasValue && !res.hasError);
		assert(res);
		assert(res.value == 0);
		assert(res.error is null);
		res = 42;
		assert(res.value == 42);
	}

	// T == void
	{
		auto res = Expected!(void, string).init;
		static assert(!__traits(compiles, res.hasValue));
		static assert(!__traits(compiles, res.value));
		static assert(!__traits(compiles, res = "foo"));
		assert(!res.hasError);
		assert(res);
		assertThrown!Throwable(res.error);
	}

	// T == void
	{
		auto res = Expected!(void, string, EnableDefaultConstructor).init;
		static assert(!__traits(compiles, res.hasValue));
		static assert(!__traits(compiles, res.value));
		assert(!res.hasError);
		assert(res.state == Expected!(void, string, EnableDefaultConstructor).State.empty);
		assert(res);
		assert(res.error is null);
		res = "foo";
		assert(res.error == "foo");
	}
}

// Default constructor - disabled
unittest
{
	static assert(!__traits(compiles, Expected!(int, string)()));
}

// Default constructor - enabled
@system nothrow unittest
{
	struct EnableDefaultConstructor { static immutable bool enableDefaultConstructor = true; }
	{
		auto res = Expected!(int, string, EnableDefaultConstructor)();
		assert(!res.hasValue && !res.hasError);
		assert(res);
		assert(res.value == 0);
		assert(res.error is null);
		res = 42;
		assert(res);
		assert(res.value == 42);
	}

	{
		auto res = Expected!(void, string, EnableDefaultConstructor)();
		assert(!res.hasError);
		assert(res);
		assert(res.error is null);
		res = "foo";
		assert(res.hasError);
		assert(!res);
		assert(res.error == "foo");
	}
}

// Default types
nothrow @nogc unittest
{
	auto res = Expected!(int)(42);
	assert(res);
	assert(res.hasValue && !res.hasError);
	assert(res.value == 42);
	res.value = 43;
	assert(res.value == 43);
}

// Default types with const payload
nothrow @nogc unittest
{
	alias Exp = Expected!(const(int));
	static assert(is(typeof(Exp.init.value) == const(int)));
	auto res = Exp(42);
	assert(res);
	assert(res.hasValue && !res.hasError);
	assert(res.value == 42);
	static assert(!__traits(compiles, res.value = res.value));
}

// Default types with immutable payload
unittest
{
	alias Exp = Expected!(immutable(int));
	static assert(is(typeof(Exp.init.value) == immutable(int)));
	auto res = Exp(42);
	assert(res);
	assert(res.hasValue && !res.hasError);
	assert(res.value == 42);
	static assert(!__traits(compiles, res.value = res.value));
}

// opAssign
@system nothrow unittest
{
	struct EnableDefaultConstructor { static immutable bool enableDefaultConstructor = true; }
	// value
	{
		auto res = Expected!(int, string, EnableDefaultConstructor).init;
		res = 42;
		assert(res);
		assert(res.hasValue && !res.hasError);
		assert(res.value == 42);
		res = 43;
		assertThrown!Throwable(res = "foo");
	}

	// error
	{
		auto res = Expected!(int, string, EnableDefaultConstructor)("42");
		assert(!res.hasValue && res.hasError);
		assert(res.error == "42");
		res = "foo";
		assert(res.error == "foo");
		assertThrown!Throwable(res = 42);
	}
}

/// Same types
@system nothrow unittest
{
	{
		alias Exp = Expected!(int, int);
		auto res = Exp(42);
		assert(res);
		assert(res.hasValue && !res.hasError);
		assert(res.value == 42);
		assertThrown!Throwable(res.error());
	}

	// const mix
	{
		alias Exp = Expected!(const(int), int);
		auto res = Exp(const int(42));
		auto val = res.value;
		static assert(is(typeof(val) == const int));
		assert(res);
		assert(res.hasValue && !res.hasError);
		assert(res.value == 42);
		assertThrown!Throwable(res.error);
	}

	// const mix
	{
		alias Exp = Expected!(const(int), int);
		auto res = Exp(42);
		auto err = res.error;
		static assert(is(typeof(err) == int));
		assert(!res);
		assert(!res.hasValue && res.hasError);
		assert(res.error == 42);
		assertThrown!Throwable(res.value);
	}

	// immutable mix
	{
		alias Exp = Expected!(immutable(int), int);
		auto res = Exp(immutable int(42));
		auto val = res.value;
		static assert(is(typeof(val) == immutable int));
		assert(res);
		assert(res.hasValue && !res.hasError);
		assert(res.value == 42);
		assertThrown!Throwable(res.error);
	}

	// immutable mix
	{
		alias Exp = Expected!(immutable(int), int);
		auto res = Exp(42);
		auto err = res.error;
		static assert(is(typeof(err) == int));
		assert(!res);
		assert(!res.hasValue && res.hasError);
		assert(res.error == 42);
		assertThrown!Throwable(res.value);
	}

	// immutable mix reverse
	{
		alias Exp = Expected!(int, immutable(int));
		auto res = Exp(immutable int(42));
		auto err = res.error;
		static assert(is(typeof(err) == immutable int));
		assert(!res);
		assert(!res.hasValue && res.hasError);
		assert(res.error == 42);
		assertThrown!Throwable(res.value);
	}

	// immutable mix reverse
	{
		alias Exp = Expected!(int, immutable(int));
		auto res = Exp(42);
		auto val = res.value;
		static assert(is(typeof(val) == int));
		assert(res);
		assert(res.hasValue && !res.hasError);
		assert(res.value == 42);
		assertThrown!Throwable(res.error);
	}
}

// void payload
nothrow @nogc unittest
{
	alias Exp = Expected!(void, int);
	static assert (!__traits(hasMember, Exp, "hasValue"));
	static assert (!__traits(hasMember, Exp, "value"));

	{
		auto res = Exp();
		assert(res);
		assert(!res.hasError);
	}

	{
		auto res = Exp(42);
		assert(!res);
		assert(res.hasError);
		assert(res.error == 42);
	}
}

// opEquals
unittest
{
	assert(expected(42) == 42);
	assert(expected(42) != 43);
	assert(expected("foo") == "foo");
	assert(expected("foo") != "bar");
	assert(expected("foo") == cast(const string)"foo");
	assert(expected("foo") == cast(immutable string)"foo");
	assert(expected(42) == expected(42));
	assert(expected(42) != expected(43));
	assert(expected(42) != unexpected!int("42"));

	static assert(!__traits(compiles, unexpected("foo") == "foo"));
	assert(unexpected(42) == unexpected(42));
	assert(unexpected(42) != unexpected(43));
	assert(unexpected("foo") == unexpected("foo"));
	assert(unexpected("foo") != unexpected("bar"));
}

//FIXME: doesn't work - some older dmd error
static if (__VERSION__ >= 2082)
{
	// toHash
	unittest
	{
		assert(expected(42).hashOf == 42.hashOf);
		assert(expected(42).hashOf != 43.hashOf);
		assert(expected(42).hashOf == expected(42).hashOf);
		assert(expected(42).hashOf != expected(43).hashOf);
		assert(expected(42).hashOf == expected!bool(42).hashOf);
		assert(expected(42).hashOf != unexpected("foo").hashOf);
		assert(unexpected("foo").hashOf == unexpected("foo").hashOf);
	}
}

/// range interface
unittest
{
	{
		auto r = expected(42);
		assert(!r.empty);
		assert(r.front == 42);
		r.popFront();
		assert(r.empty);
	}

	{
		auto r = unexpected!int("foo");
		assert(r.empty);
	}

	{
		auto r = unexpected("foo");
		static assert(!__traits(compiles, r.empty));
		static assert(!__traits(compiles, r.front));
		static assert(!__traits(compiles, r.popFront));
	}
}
