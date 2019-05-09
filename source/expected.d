/++
This module is implementing the Expected idiom.

See the [Andrei Alexandrescu’s talk (Systematic Error Handling in C++](http://channel9.msdn.com/Shows/Going+Deep/C-and-Beyond-2012-Andrei-Alexandrescu-Systematic-Error-Handling-in-C)
and [its slides](https://skydrive.live.com/?cid=f1b8ff18a2aec5c5&id=F1B8FF18A2AEC5C5!1158).

Or more recent ["Expect the Expected"](https://www.youtube.com/watch?v=nVzgkepAg5Y) by Andrei Alexandrescu for further background.

It is also inspired by C++'s proposed [std::expected](https://wg21.link/p0323) and [Rust's](https://www.rust-lang.org/) [Result](https://doc.rust-lang.org/std/result/).

Similar work is [expectations](http://code.dlang.org/packages/expectations) by Paul Backus.

## Main features

$(LIST
    * lightweight, no other external dependencies
    * works with `pure`, `@safe`, `@nogc`, `nothrow`, and `immutable`
    * provides methods: `ok`, `err`, `consume`, `andThen`, `orElse`, `map`, `mapError`, `mapOrElse`
    * type inference for ease of use with `ok` and `err`
    * allows to use same types for `T` and `E`
    * allows to define $(LREF Expected) without value (`void` for `T`) - can be disabled with custom `Hook`
    * provides facility to change the $(LREF Expected) behavior by custom `Hook` implementation using the Design by introspection paradigm.
    * can enforce result check (with a cost)
    * can behave like a normal `Exception` handled code by changing the used `Hook` implementation
    * range interface
)

## Description

Actual $(LREF Expected) type is defined as $(D Expected!(T, E, Hook)), where:

$(LIST
    * `T` defines type of the success value
    * `E` defines type of the error
    * `Hook` defines behavior of the $(LREF Expected)
)

Default type for error is `string`, i.e. `Expected!int` is the same as `Expected!(int, string)`.

$(LREF Abort) is used as a default hook.

### Hooks

$(LREF Expected) has customizable behavior with the help of a third type parameter,
`Hook`. Depending on what methods `Hook` defines, core operations on the
$(LREF Expected) may be verified or completely redefined.
If `Hook` defines no method at all and carries no state, there is no change in
default behavior.

This module provides a few predefined hooks (below) that add useful behavior to
$(LREF Expected):

$(BOOKTABLE ,
    $(TR $(TD $(LREF Abort)) $(TD
        Fails every incorrect operation with a call to `assert(0)`.
        It is the default third parameter, i.e. $(D Expected!short) is the same as
        $(D Expected!(short, string, Abort)).
    ))
    $(TR $(TD $(LREF Throw)) $(TD
        Fails every incorrect operation by throwing an exception.
    ))
    $(TR $(TD $(LREF AsException)) $(TD
        With this hook implementation $(LREF Expected) behaves just like regular
        $(D Exception) handled code.

        That means when function returns $(LREF expected) value, it returns instance
        of $(LREF Expected) with a success value.
        But when it tries to return error, $(D Exception) is thrown right away,
        i.e. $(LREF Expected) fails in constructor.
    ))
    $(TR $(TD $(LREF RCAbort)) $(TD
        Similar to $(LREF Abort) hook but uses reference counted payload instead
        which enables checking if the caller properly checked result of the
        $(LREF Expected).
    ))
)

The hook's members are looked up statically in a Design by Introspection manner
and are all optional. The table below illustrates the members that a hook type
may define and their influence over the behavior of the `Checked` type using it.
In the table, `hook` is an alias for `Hook` if the type `Hook` does not
introduce any state, or an object of type `Hook` otherwise.

$(TABLE_ROWS
    * + Hook member
      + Semantics in Expected!(T, E, Hook)
    * - `enableDefaultConstructor`
      - If defined, $(LREF Expected) would have enabled or disabled default constructor
        based on it's `bool` value. Default constructor is disabled by default.
        `opAssign` for value and error types is generated if default constructor is enabled.
    * - `enableCopyConstructor`
      - If defined, $(LREF Expected) would have enabled or disabled copy constructor based
        on it's `bool` value. It is enabled by default. When disabled, it enables automatic
        check if the result was checked either for value or error.
        When not checked it calls $(D hook.onUnchecked) if provided.

        $(NOTE WARNING: As currently it's not possible to change internal state of `const`
        or `immutable` object, automatic checking would't work on these. Hopefully with
        `__mutable` proposal..)
    * - `enableRefCountedPayload`
      - Set $(LREF Expected) instances to use reference counted payload storage. It's usefull
        when combined with `onUnchecked` to forcibly check that the result was checked for value
        or error.
    * - `enableVoidValue`
      - Defines if $(LREF Expected) supports `void` values. It's enabled by default so this
        hook can be used to disable it.
    * - `onAccessEmptyValue`
      - If value is accessed on unitialized $(LREF Expected) or $(LREF Expected) with error
        value, $(D hook.onAccessEmptyValue!E(err)) is called. If hook doesn't implement the
        handler, `T.init` is returned.
    * - `onAccessEmptyError`
      - If error is accessed on unitialized $(LREF Expected) or $(LREF Expected) with value,
        $(D hook.onAccessEmptyError()) is called. If hook doesn't implement the handler,
        `E.init` is returned.
    * - `onUnchecked`
      - If the result of $(LREF Expected) isn't checked, $(D hook.onUnchecked()) is called to
        handle the error. If hook doesn't implement the handler, assert is thrown.
        $(NOTE Note that `hook.enableCopyConstructor` must be `false` or `hook.enableRefCountedPayload`
        must be `true` for checks to work.)
    * - `onValueSet`
      - $(D hook.onValueSet!T(val)) function is called when success value is being set to
        $(LREF Expected). It can be used for loging purposes, etc.
    * - `onErrorSet`
      - $(D hook.onErrorSet!E(err)) function is called when error value is being set to
        $(LREF Expected). This hook function is used by $(LREF AsException) hook implementation
        to change `Expected` idiom to normal `Exception` handling behavior.
)

License: BSL-1.0
Author: Tomáš Chaloupka
+/

//TODO: collect errno function call - see https://dlang.org/phobos/std_exception.html#ErrnoException

module expected;

/// $(H3 Basic usage)
@("Basic usage example")
@safe unittest
{
    auto foo(int i) {
        if (i == 0) return err!int("oops");
        return ok(42 / i);
    }

    auto bar(int i) {
        if (i == 0) throw new Exception("err");
        return i-1;
    }

    // basic checks
    assert(foo(2));
    assert(foo(2).hasValue);
    assert(!foo(2).hasError);
    assert(foo(2).value == 21);

    assert(!foo(0));
    assert(!foo(0).hasValue);
    assert(foo(0).hasError);
    assert(foo(0).error == "oops");

    // void result
    assert(ok()); // no error -> success
    assert(!ok().hasError);
    // assert(err("foo").hasValue); // doesn't have hasValue and value properties

    // expected from throwing function
    assert(consume!bar(1) == 0);
    assert(consume!bar(0).error.msg == "err");

    // orElse
    assert(foo(2).orElse!(() => 0) == 21);
    assert(foo(0).orElse(100) == 100);

    // andThen
    assert(foo(2).andThen(foo(6)) == 7);
    assert(foo(0).andThen(foo(6)).error == "oops");

    // map
    assert(foo(2).map!(a => a*2).map!(a => a - 2) == 40);
    assert(foo(0).map!(a => a*2).map!(a => a - 2).error == "oops");

    // mapError
    assert(foo(0).mapError!(e => "OOPS").error == "OOPS");
    assert(foo(2).mapError!(e => "OOPS") == 21);

    // mapOrElse
    assert(foo(2).mapOrElse!(v => v*2, e => 0) == 42);
    assert(foo(0).mapOrElse!(v => v*2, e => 0) == 0);
}

/// $(H3 Advanced usage - behavior modification)
@("Advanced usage example")
unittest
{
    import exp = expected;

    // define our Expected type using Exception as Error values
    // and Throw hook, which throws when empty value or error is accessed
    template Expected(T)
    {
        alias Expected = exp.Expected!(T, Exception, Throw);
    }

    // create wrappers for simplified usage of our Expected
    auto ok(T)(T val) { return exp.ok!(Exception, Throw)(val); }
    auto err(T)(Exception err) { return exp.err!(T, Throw)(err); }

    // use it as normal
    assert(ok(42) == 42);
    assert(err!int(new Exception("foo")).orElse(0) == 0);
    assertThrown(ok(42).error);
    assertThrown(err!int(new Exception("bar")).value);
}

version (unittest) {
    import std.algorithm : reverse;
    import std.exception : assertThrown, collectExceptionMsg;
}

@safe:

/++
    `Expected!(T, E)` is a type that represents either success or failure.

    Type `T` is used for success value.
    If `T` is `void`, then $(LREF Expected) can only hold error value and is considered a success when there is no error value.

    Type `E` is used for error value.
    The default type for the error value is `string`.

    Default behavior of $(LREF Expected) can be modified by the `Hook` template parameter.

    Params:
        T    = represents type of the expected value
        E    = represents type of the error value.
        Hook = defines the $(LREF Expected) type behavior
+/
struct Expected(T, E = string, Hook = Abort)
    if (!is(E == void) && (isVoidValueEnabled!Hook || !is(T == void)))
{
    import std.algorithm : move;
    import std.meta : AliasSeq, Filter, NoDuplicates;
    import std.traits: isAssignable, isCopyable, hasIndirections, Unqual;

    private template noVoid(T) { enum noVoid = !is(T == void); } // Erase removes qualifiers
    private alias Types = NoDuplicates!(Filter!(noVoid, AliasSeq!(T, E)));

    private template isMoveable(T) { enum isMoveable = __traits(compiles, (T a) { return a.move; }); }

    static foreach (i, CT; Types)
    {
        /++
            Constructs an $(LREF Expected) with value or error based on the tye of the provided.

            In case when `T == E`, it constructs $(LREF Expected) with value.

            In case when `T == void`, it constructs $(LREF Expected) with error value.

            Default constructor (if enabled) initializes $(LREF Expected) to `T.init` value.
            If `T == void`, it initializes $(LREF Expected) with no error.
        +/
        this()(auto ref CT val)
        {
            static if (isRefCountedPayloadEnabled!Hook)
            {
                static if (isCopyable!CT) initialize(val);
                else static if (isMoveable!CT) initialize(move(val));
                else static assert(0, "Can't consume " ~ CT.stringof);
            }
            else
            {
                static if (isCopyable!CT) storage = Payload(val);
                else static if (isMoveable!CT) storage = Payload(move(val));
                else static assert(0, "Can't consume " ~ CT.stringof);
            }
            setState!CT();

            static if (hasOnValueSet!(Hook, CT)) { if (state == State.value) __traits(getMember, Hook, "onValueSet")(val); }
            static if (hasOnErrorSet!(Hook, CT)) { if (state == State.error) __traits(getMember, Hook, "onErrorSet")(val); }
        }

        // static if (isCopyable!CT)
        // {
        //     / ditto
        //     this()(auto ref const(CT) val) const
        //     {
        //         storage = const(Payload)(val);
        //         setState!CT();

        //         static if (hasOnValueSet!(Hook, CT)) { if (state == State.value) __traits(getMember, Hook, "onValueSet")(val); }
        //         static if (hasOnErrorSet!(Hook, CT)) { if (state == State.error) __traits(getMember, Hook, "onErrorSet")(val); }
        //     }

        //     /// ditto
        //     this()(auto ref immutable(CT) val) immutable
        //     {
        //         storage = immutable(Payload)(val);
        //         setState!CT();

        //         static if (hasOnValueSet!(Hook, CT)) { if (state == State.value) __traits(getMember, Hook, "onValueSet")(val); }
        //         static if (hasOnErrorSet!(Hook, CT)) { if (state == State.error) __traits(getMember, Hook, "onErrorSet")(val); }
        //     }
        // }
        // else
        // {
        //     @disable this(const(CT) val) const;
        //     @disable this(immutable(CT) val) immutable;
        // }
    }

    // generate constructor with flag to determine type of value
    static if (Types.length == 1 && !is(T == void))
    {
        /++ Constructs an $(LREF Expected) with value or error based on the provided flag.
            This constructor is available only for cases when value and error has the same type,
            so we can still construct $(LREF Expected) with value or error.

            Params:
                val     = Value to set as value or error
                success = If `true`, $(LREF Expected) with value is created, $(LREF Expected) with error otherwise.
        +/
        this()(auto ref E val, bool success)
        {
            static if (isRefCountedPayloadEnabled!Hook)
            {
                static if (isCopyable!E) initialize(val);
                else static if (isMoveable!E) initialize(move(val));
                else static assert(0, "Can't consume " ~ E.stringof);
            }
            else
            {
                static if (isCopyable!E) storage = Payload(val);
                else static if (isMoveable!E) storage = Payload(val);
                else static assert(0, "Can't consume " ~ E.stringof);
            }
            setState!E(success ? State.value : State.error);

            static if (hasOnValueSet!(Hook, E)) { if (state == State.value) __traits(getMember, Hook, "onValueSet")(val); }
            static if (hasOnErrorSet!(Hook, E)) { if (state == State.error) __traits(getMember, Hook, "onErrorSet")(val); }
        }

        // static if (isCopyable!E)
        // {
        //     /// ditto
        //     this()(auto ref const(E) val, bool success) const
        //     {
        //         storage = const(Payload)(val);
        //         setState!E(success ? State.value : State.error);

        //         static if (hasOnValueSet!(Hook, E)) { if (state == State.value) __traits(getMember, Hook, "onValueSet")(val); }
        //         static if (hasOnErrorSet!(Hook, E)) { if (state == State.error) __traits(getMember, Hook, "onErrorSet")(val); }
        //     }

        //     /// ditto
        //     this()(auto ref immutable(E) val, bool success) immutable
        //     {
        //         storage = immutable(Payload)(val);
        //         setState!E(success ? State.value : State.error);

        //         static if (hasOnValueSet!(Hook, E)) { if (state == State.value) __traits(getMember, Hook, "onValueSet")(val); }
        //         static if (hasOnErrorSet!(Hook, E)) { if (state == State.error) __traits(getMember, Hook, "onErrorSet")(val); }
        //     }
        // }
        // else
        // {
        //     @disable this(const(E) val, bool success) const;
        //     @disable this(immutable(E) val, bool success) immutable;
        // }
    }

    static if (!is(T == void) && !isDefaultConstructorEnabled!Hook) @disable this();

    static if (!isCopyConstructorEnabled!Hook) @disable this(this);

    static if (isChecked!Hook || isRefCountedPayloadEnabled!Hook)
    {
        ~this()
        {
            static void onUnchecked()
            {
                static if (hasOnUnchecked!Hook) __traits(getMember, Hook, "onUnchecked")();
                else assert(0, "unchecked result");
            }

            static if (isRefCountedPayloadEnabled!Hook)
            {
                if (!storage) return;
                assert(storage.count > 0);

                if (--storage.count) return;

                // Done, deallocate
                static if (isChecked!Hook) bool ch = checked;
                destroy(storage.payload);
                static if (enableGCScan) pureGcRemoveRange(&storage.payload);

                pureFree(storage);
                storage = null;

                static if (isChecked!Hook) { if (!ch) onUnchecked(); }
            }
            else static if (isChecked!Hook) { if (!checked) onUnchecked(); }
        }
    }

    static if (isDefaultConstructorEnabled!Hook)
    {
        static foreach (i, CT; Types)
        {
            static if (isAssignable!CT)
            {
                /++ Assigns a value or error to an $(LREF Expected).

                    Note: This is only allowed when default constructor is also enabled.
                +/
                void opAssign()(auto ref CT rhs)
                {
                    setState!CT(); // check state asserts before change
                    auto s = state;
                    static if (isRefCountedPayloadEnabled!Hook)
                    {
                        if (!storage) initialize(rhs);
                        else storage.payload = Payload(rhs);
                    }
                    else storage = Payload(rhs);
                    setState!(CT)(s); // set previous state

                    static if (hasOnValueSet!(Hook, CT)) { if (state == State.value) __traits(getMember, Hook, "onValueSet")(val); }
                    static if (hasOnErrorSet!(Hook, CT)) { if (state == State.error) __traits(getMember, Hook, "onErrorSet")(val); }
                }
            }
        }
    }

    //damn these are ugly :(
    static if (!isChecked!Hook) {
        /++ Implicit conversion to bool.
            Returns: `true` if there is no error set, `false` otherwise.
        +/
        bool opCast(T)() const if (is(T == bool)) { return !this.hasError; }
    } else {
        /// ditto
        bool opCast(T)() if (is(T == bool)) { return !this.hasError; }
    }

    static if (!is(T == void))
    {
        static if (!isChecked!Hook) {
            /++ Checks whether this $(LREF Expected) object contains a specific expected value.

                * `opEquals` for the value is available only when `T != void`.
                * `opEquals` for the error isn't available, use equality test for $(LREF Expected) in that case.
            +/
            bool opEquals()(const auto ref T rhs) const
            {
                return hasValue && value == rhs;
            }
        } else {
            /// ditto
            bool opEquals()(auto ref T rhs) { return hasValue && value == rhs; }
        }
    }

    static if (!isChecked!Hook) {
        /// Checks whether this $(LREF Expected) object and `rhs` contain the same expected value or error value.
        bool opEquals()(const auto ref Expected!(T, E, Hook) rhs) const
        {
            if (state != rhs.state) return false;
            static if (!is(T == void)) { if (hasValue) return value == rhs.value; }
            return error == rhs.error;
        }
    } else {
        /// ditto
        bool opEquals()(auto ref Expected!(T, E, Hook) rhs)
        {
            if (state != rhs.state) return false;
            static if (!is(T == void)) { if (hasValue) return value == rhs.value; }
            return error == rhs.error;
        }
    }

    static if (!isChecked!Hook) {
        /++ Calculates the hash value of the $(LREF Expected) in a way that iff it has a value,
            it returns hash of the value.
            Hash is computed using internal state and storage of the $(LREF Expected) otherwise.
        +/
        size_t toHash()() const nothrow
        {
            static if (!is(T == void)) { if (hasValue) return value.hashOf; }
            return storage.hashOf(state);
        }
    } else {
        /// ditto
        size_t toHash()() nothrow
        {
            static if (!is(T == void)) { if (hasValue) return value.hashOf; }
            return storage.hashOf(state);
        }
    }

    static if (!is(T == void))
    {
        static if (!isChecked!Hook) {
            /// Checks if $(LREF Expected) has value
            @property bool hasValue()() const { return state == State.value; }
        }
        else {
            /// ditto
            @property bool hasValue()()
            {
                checked = true;
                return state == State.value;
            }
        }

        static if (!isChecked!Hook) {
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
                        __traits(getMember, Hook, "onAccessEmptyValue")(state == State.error ? getError() : E.init);
                    else return T.init;
                }
                return getValue();
            }
        } else {
            @property auto ref T value()
            {
                checked = true;

                if (state != State.value)
                {
                    static if (hasOnAccessEmptyValue!(Hook, E))
                        __traits(getMember, Hook, "onAccessEmptyValue")(state == State.error ? getError() : E.init);
                    else return T.init;
                }
                return getValue();
            }
        }
    }

    static if (!isChecked!Hook) {
        /// Checks if $(LREF Expected) has error
        @property bool hasError()() const { return state == State.error; }
    } else {
        /// ditto
        @property bool hasError()()
        {
            checked = true;
            return state == State.error;
        }
    }

    static if (!isChecked!Hook) {
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
            return getError;
        }
    } else {
        @property auto ref E error()
        {
            checked = true;

            if (state != State.error)
            {
                static if (hasOnAccessEmptyError!Hook) __traits(getMember, Hook, "onAccessEmptyError")();
                else return E.init;
            }
            return getError;
        }
    }

    // range interface
    static if (!is(T == void))
    {
        static if (!isChecked!Hook) {
            /++ Range interface defined by `empty`, `front`, `popFront`.
                Yields one value if $(LREF Expected) has value.

                If `T == void`, range interface isn't defined.
            +/
            @property bool empty() const { return state != State.value; }

            /// ditto
            @property auto ref inout(T) front() inout { return value; }
        } else {
            @property bool empty() { checked = true; return state != State.value; }

            /// ditto
            @property auto ref T front() { return value; }
        }

        /// ditto
        void popFront() { state = State.empty; }
    }

    private:

    //FIXME: can probably be union instead, but that doesn't work well with destructors and copy constructors/postblits
    //and need to be handled manually - so for now we use a safer variant
    struct Payload
    {
        Types values;

        // generate payload constructors
        static foreach (i, CT; Types)
        {
            this()(auto ref CT val)
            {
                static if (isCopyable!CT) __traits(getMember, Payload, "values")[i] = val;
                else static if (isMoveable!CT) __traits(getMember, Payload, "values")[i] = move(val);
                else static assert(0, "Can't consume " ~ CT.stringof);
            }

            // static if (isCopyable!CT)
            // {
            //     this()(auto ref const(CT) val) const { __traits(getMember, Payload, "values")[i] = val; }
            //     this()(auto ref immutable(CT) val) immutable { __traits(getMember, Payload, "values")[i] = val; }
            // }
            // else
            // {
            //     @disable this(const(CT) val) const;
            //     @disable this(immutable(CT) val) immutable;
            // }
        }
    }

    static if (isRefCountedPayloadEnabled!Hook)
    {
        version (D_BetterC) enum enableGCScan = false;
        else enum enableGCScan = hasIndirections!Payload;

        // purify memory management functions - see https://github.com/dlang/phobos/pull/4832
        extern(C) pure nothrow @nogc static
        {
            pragma(mangle, "malloc") void* pureMalloc(size_t);
            pragma(mangle, "free") void pureFree( void *ptr );
            static if (enableGCScan)
            {
                pragma(mangle, "calloc") void* pureCalloc(size_t nmemb, size_t size);
                pragma(mangle, "gc_addRange") void pureGcAddRange( in void* p, size_t sz, const TypeInfo ti = null );
                pragma(mangle, "gc_removeRange") void pureGcRemoveRange( in void* p );
            }
        }

        struct Impl
        {
            Payload payload;
            State state;
            size_t count;
            static if (isChecked!Hook) bool checked;
        }

        void initialize(A...)(auto ref A args)
        {
            import std.conv : emplace;

            allocateStore();
            emplace(&storage.payload, args);
            storage.count = 1;
            storage.state = State.empty;
            static if (isChecked!Hook) storage.checked = false;
        }

        void allocateStore() nothrow pure @trusted
        {
            assert(!storage);
            static if (enableGCScan)
            {
                storage = cast(Impl*) pureCalloc(1, Impl.sizeof);
                if (!storage) assert(0, "Memory allocation failed");
                pureGcAddRange(&storage.payload, Payload.sizeof);
            }
            else
            {
                storage = cast(Impl*) pureMalloc(Impl.sizeof);
                if (!storage) assert(0, "Memory allocation failed");
            }
        }

        Impl* storage;

        @property nothrow @safe pure @nogc
        size_t refCount() const { return storage !is null ? storage.count : 0; }

        @property nothrow @safe pure @nogc
        State state() const { return storage !is null ? storage.state : State.empty; }

        @property nothrow @safe pure @nogc
        void state(State state) { assert(storage); storage.state = state; }

        static if (isChecked!Hook)
        {
            @property nothrow @safe pure @nogc
            bool checked() const { assert(storage); return storage.checked; }

            @property nothrow @safe pure @nogc
            void checked(bool ch) { assert(storage); storage.checked = ch; }
        }

        ref inout(E) getError()() inout
        {
            assert(storage);
            static if (__VERSION__ < 2078) // workaround - see: https://issues.dlang.org/show_bug.cgi?id=15094
            {
                auto p = &storage.payload;
                static if (Types.length == 1) return __traits(getMember, p, "values")[0];
                else return __traits(getMember, p, "values")[1];
            }
            else
            {
                static if (Types.length == 1) return __traits(getMember, storage.payload, "values")[0];
                else return __traits(getMember, storage.payload, "values")[1];
            }
        }

        static if (!is(T == void))
        {
            ref inout(T) getValue()() inout
            {
                assert(storage);
                static if (__VERSION__ < 2078) // workaround - see: https://issues.dlang.org/show_bug.cgi?id=15094
                {
                    auto p = &storage.payload;
                    return __traits(getMember, p, "values")[0];
                }
                else return __traits(getMember, storage.payload, "values")[0];
            }
        }

        this(this) @safe pure nothrow @nogc
        {
            if (!storage) return;
            ++storage.count;
        }
    }
    else
    {
        Payload storage;
        State state = State.empty;
        static if (isChecked!Hook) bool checked = false;

        ref inout(E) getError()() inout
        {
            static if (Types.length == 1) return __traits(getMember, storage, "values")[0];
            else return __traits(getMember, storage, "values")[1];
        }

        static if (!is(T == void))
        {
            ref inout(T) getValue()() inout
            {
                return __traits(getMember, storage, "values")[0];
            }
        }
    }

    enum State : ubyte { empty, value, error }

    void setState(MT)(State known = State.empty)
    {
        State s;
        if (known != State.empty) s = known;
        else
        {
            static if (Types.length == 1 && is(T == void)) s = State.error;
            else static if (Types.length == 1 || is(MT == T)) s = State.value;
            else s = State.error;
        }

        //TODO: change with Hook?
        assert(state == State.empty || state == s, "Can't change meaning of already set Expected type");
        state = s;
    }
}

/++ Template to determine if hook enables or disables copy constructor.

    It is enabled by default.

    See $(LREF hasOnUnchecked) handler, which can be used in combination with disabled
    copy constructor to enforce that the result is checked.

    $(WARNING If copy constructor is disabled, it severely limits function chaining
    as $(LREF Expected) needs to be passed as rvalue in that case.)
+/
template isCopyConstructorEnabled(Hook)
{
    static if (__traits(hasMember, Hook, "enableCopyConstructor"))
    {
        static assert(
            is(typeof(__traits(getMember, Hook, "enableCopyConstructor")) : bool),
            "Hook's enableCopyConstructor is expected to be of type bool"
        );
        enum isCopyConstructorEnabled = __traits(getMember, Hook, "enableCopyConstructor");
    }
    else enum isCopyConstructorEnabled = true;
}

///
@("isCopyConstructorEnabled")
unittest
{
    struct Foo {}
    struct Bar { static immutable bool enableCopyConstructor = false; }
    static assert(isCopyConstructorEnabled!Foo);
    static assert(!isCopyConstructorEnabled!Bar);
}

/++ Template to determine if hook defines that the $(LREF Expected) storage should
    use refcounted state storage.

    If this is enabled, payload is mallocated on the heap and dealocated with the
    destruction of last $(Expected) instance.

    See $(LREF hasOnUnchecked) handler, which can be used in combination with refcounted
    payload to enforce that the result is checked.
+/
template isRefCountedPayloadEnabled(Hook)
{
    static if (__traits(hasMember, Hook, "enableRefCountedPayload"))
    {
        static assert(
            is(typeof(__traits(getMember, Hook, "enableRefCountedPayload")) : bool),
            "Hook's enableCopyConstructor is expected to be of type bool"
        );
        enum isRefCountedPayloadEnabled = __traits(getMember, Hook, "enableRefCountedPayload");
        static assert (
            !isRefCountedPayloadEnabled || isCopyConstructorEnabled!Hook,
            "Refcounted payload wouldn't work without copy constructor enabled"
        );
    }
    else enum isRefCountedPayloadEnabled = false;
}

///
@("isRefCountedPayloadEnabled")
unittest
{
    struct Foo {}
    struct Bar {
        static immutable bool enableCopyConstructor = false;
        static immutable bool enableRefCountedPayload = true;
    }
    struct Hook { static immutable bool enableRefCountedPayload = true; }
    static assert(!isRefCountedPayloadEnabled!Foo);
    static assert(!__traits(compiles, isRefCountedPayloadEnabled!Bar));
    static assert(isRefCountedPayloadEnabled!Hook);
}

// just a helper to determine check behavior
private template isChecked(Hook)
{
    enum isChecked = !isCopyConstructorEnabled!Hook || isRefCountedPayloadEnabled!Hook;
}

/// Template to determine if provided Hook enables default constructor for $(LREF Expected)
template isDefaultConstructorEnabled(Hook)
{
    static if (__traits(hasMember, Hook, "enableDefaultConstructor"))
    {
        static assert(
            is(typeof(__traits(getMember, Hook, "enableDefaultConstructor")) : bool),
            "Hook's enableDefaultConstructor is expected to be of type bool"
        );
        enum isDefaultConstructorEnabled = __traits(getMember, Hook, "enableDefaultConstructor");
    }
    else enum isDefaultConstructorEnabled = false;
}

///
@("isDefaultConstructorEnabled")
unittest
{
    struct Foo {}
    struct Bar { static immutable bool enableDefaultConstructor = true; }
    static assert(!isDefaultConstructorEnabled!Foo);
    static assert(isDefaultConstructorEnabled!Bar);
}

/// Template to determine if provided Hook enables void values for $(LREF Expected)
template isVoidValueEnabled(Hook)
{
    static if (__traits(hasMember, Hook, "enableVoidValue"))
    {
        static assert(
            is(typeof(__traits(getMember, Hook, "enableVoidValue")) : bool),
            "Hook's enableVoidValue is expected to be of type bool"
        );
        enum isVoidValueEnabled = __traits(getMember, Hook, "isVoidValueEnabled");
    }
    else enum isVoidValueEnabled = true;
}

///
@("isVoidValueEnabled")
unittest
{
    struct Hook { static immutable bool enableVoidValue = false; }
    assert(!ok().hasError); // void values are enabled by default
    static assert(!__traits(compiles, ok!(string, Hook)())); // won't compile
}

/// Template to determine if hook provides function called on empty value.
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
@("hasOnAccessEmptyValue")
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
@("hasOnAccessEmptyError")
unittest
{
    struct Foo {}
    struct Bar { static void onAccessEmptyError() {} }
    static assert(!hasOnAccessEmptyError!Foo);
    static assert(hasOnAccessEmptyError!Bar);
}

/++ Template to determine if hook provides custom handler for case
    when the $(LREF Expected) result is not checked.

    For this to work it currently also has to pass $(LREF isCopyConstructorEnabled)
    as this is implemented by simple flag controled on $(LREF Expected) destructor.
+/
template hasOnUnchecked(Hook)
{
    static if (__traits(hasMember, Hook, "onUnchecked"))
    {
        static assert(
            is(typeof(__traits(getMember, Hook, "onUnchecked")())),
            "Hook's onUnchecked is expected to be callable with no arguments"
        );
        static assert(
            !isCopyConstructorEnabled!Hook || isRefCountedPayloadEnabled!Hook,
            "For unchecked check to work, it is needed to also have disabled copy constructor or enabled reference counted payload"
        );
        enum hasOnUnchecked = true;
    }
    else enum hasOnUnchecked = false;
}

///
@("hasOnUnchecked")
@system unittest
{
    struct Foo {}
    struct Bar { static void onUnchecked() { } }
    struct Hook {
        static immutable bool enableCopyConstructor = false;
        static void onUnchecked() @safe { throw new Exception("result unchecked"); }
    }

    // template checks
    static assert(!hasOnUnchecked!Foo);
    static assert(!__traits(compiles, hasOnUnchecked!Bar)); // missing disabled constructor
    static assert(hasOnUnchecked!Hook);

    // copy constructor
    auto exp = ok!(string, Hook)(42);
    auto exp2 = err!(int, Hook)("foo");
    static assert(!__traits(compiles, exp.andThen(ok!(string, Hook)(42)))); // disabled cc
    assert(exp.andThen(exp2).error == "foo"); // passed by ref so no this(this) called

    // check for checked result
    assertThrown({ ok!(string, Hook)(42); }());
    assertThrown({ err!(void, Hook)("foo"); }());
}

/++ Template to determine if hook provides function called when value is set.
+/
template hasOnValueSet(Hook, T)
{
    static if (__traits(hasMember, Hook, "onValueSet"))
    {
        static assert(
            is(typeof(__traits(getMember, Hook, "onValueSet")(T.init))),
            "Hook's onValueSet is expected to be callable with value argument"
        );
        enum hasOnValueSet = true;
    }
    else enum hasOnValueSet = false;
}

///
@("hasOnValueSet")
unittest
{
    struct Hook {
        static int lastValue;
        static void onValueSet(T)(auto ref T val) { lastValue = val; }
    }

    static assert(hasOnValueSet!(Hook, int));
    auto res = ok!(string, Hook)(42);
    assert(res.hasValue);
    assert(Hook.lastValue == 42);
}

/++ Template to determine if hook provides function called when error is set.
+/
template hasOnErrorSet(Hook, T)
{
    static if (__traits(hasMember, Hook, "onErrorSet"))
    {
        static assert(
            is(typeof(__traits(getMember, Hook, "onErrorSet")(T.init))),
            "Hook's onErrorSet is expected to be callable with error argument"
        );
        enum hasOnErrorSet = true;
    }
    else enum hasOnErrorSet = false;
}

///
@("hasOnErrorSet")
unittest
{
    struct Hook {
        static string lastErr;
        static void onErrorSet(E)(auto ref E err) { lastErr = err; }
    }

    static assert(hasOnErrorSet!(Hook, string));
    auto res = err!(int, Hook)("foo");
    assert(res.hasError);
    assert(Hook.lastErr == "foo");
}

/++ Default hook implementation for $(LREF Expected)
+/
struct Abort
{
static:
    /++ Default constructor for $(LREF Expected) is disabled.
        Same with the `opAssign`, so $(LREF Expected) can be only constructed
        once and not modified afterwards.
    +/
    immutable bool enableDefaultConstructor = false;

    /// Handler for case when empty value is accessed.
    void onAccessEmptyValue(E)(E err) nothrow @nogc
    {
        assert(0, "Value not set");
    }

    /// Handler for case when empty error is accessed.
    void onAccessEmptyError() nothrow @nogc
    {
        assert(0, "Error not set");
    }
}

///
@("Abort")
@system unittest
{
    static assert(!isDefaultConstructorEnabled!Abort);
    static assert(hasOnAccessEmptyValue!(Abort, string));
    static assert(hasOnAccessEmptyValue!(Abort, int));
    static assert(hasOnAccessEmptyError!Abort);

    assertThrown!Throwable(ok(42).error);
    assertThrown!Throwable(err!int("foo").value);
}

/++ Hook implementation that throws exceptions instead of default assert behavior.
+/
struct Throw
{
static:

    /++ Default constructor for $(LREF Expected) is disabled.
        Same with the `opAssign`, so $(LREF Expected) can be only constructed
        once and not modified afterwards.
    +/
    immutable bool enableDefaultConstructor = false;

    /++ Handler for case when empty value is accessed.

        Throws:
            If `E` inherits from `Throwable`, the error value is thrown.
            Otherwise, an [Unexpected] instance containing the error value is
            thrown.
    +/
    void onAccessEmptyValue(E)(E err)
    {
        import std.traits : Unqual;
        static if(is(Unqual!E : Throwable)) throw err;
        else throw new Unexpected!E(err);
    }

    /// Handler for case when empty error is accessed.
    void onAccessEmptyError()
    {
        throw new Unexpected!string("Can't access error on expected value");
    }
}

///
@("Throw")
unittest
{
    static assert(!isDefaultConstructorEnabled!Throw);
    static assert(hasOnAccessEmptyValue!(Throw, string));
    static assert(hasOnAccessEmptyValue!(Throw, int));
    static assert(hasOnAccessEmptyError!Throw);

    assertThrown!(Unexpected!string)(ok!(string, Throw)(42).error);
    assertThrown!(Unexpected!string)(err!(int, Throw)("foo").value);
    assertThrown!(Unexpected!int)(err!(bool, Throw)(-1).value);
}

/++ Hook implementation that behaves like a thrown exception.
    It throws $(D Exception) right when the $(LREF Expected) with error is initialized.

    With this, one can easily change the code behavior between `Expected` idiom or plain `Exception`s.
+/
struct AsException
{
static:

    /++ Default constructor for $(LREF Expected) is disabled.
        Same with the `opAssign`, so $(LREF Expected) can be only constructed
        once and not modified afterwards.
    +/
    immutable bool enableDefaultConstructor = false;

    /++ Handler for case when empty error is accessed.
    +/
    void onErrorSet(E)(auto ref E err)
    {
        static if (is(E : Throwable)) throw E;
        else throw new Unexpected!E(err);
    }
}

///
@("AsException")
unittest
{
    static assert(!isDefaultConstructorEnabled!AsException);
    static assert(hasOnErrorSet!(AsException, string));

    auto div(int a, int b) {
        if (b != 0) return ok!(string, AsException)(a / b);
        return err!(int, AsException)("oops");
    }

    assert(div(10, 2) == 5);
    assert(collectExceptionMsg!(Unexpected!string)(div(1, 0)) == "oops");
}

/++ Hook implementation that behaves same as $(LREF Abort) hook, but uses refcounted payload
    instead, which also enables us to check, if the result was properly checked before it is
    discarded.
+/
struct RCAbort
{
static:
    /++ Default constructor for $(LREF Expected) is disabled.
        Same with the `opAssign`, so $(LREF Expected) can be only constructed
        once and not modified afterwards.
    +/
    immutable bool enableDefaultConstructor = false;

    /// Copy constructor is enabled so the reference counting makes sense
    immutable bool enableCopyConstructor = true;

    /// Enabled reference counted payload
    immutable bool enableRefCountedPayload = true;

    void onUnchecked() pure nothrow @nogc { assert(0, "result unchecked"); }
}

///
@("RCAbort")
@system unittest
{
    // behavior checks
    static assert(!isDefaultConstructorEnabled!RCAbort);
    static assert(isCopyConstructorEnabled!RCAbort);
    static assert(isRefCountedPayloadEnabled!RCAbort);

    // basics
    assert(ok!(string, RCAbort)(42) == 42);
    assert(err!(int, RCAbort)("foo").error == "foo");

    // checked
    {
        auto res = ok!(string, RCAbort)(42);
        assert(!res.checked);
        assert(res);
        assert(res.checked);
    }

    // unchecked - throws assert
    assertThrown!Throwable({ ok!(string, RCAbort)(42); }());

    {
        auto res = ok!(string, RCAbort)(42);
        {
            auto res2 = res;
            assert(!res.checked);
            assert(res.refCount == 2);
            assert(res2.refCount == 2);
        }
        assert(res.refCount == 1);
        assert(res.hasValue);
    }

    // chaining
    assert(err!(int, RCAbort)("foo").orElse!(() => ok!(string, RCAbort)(42)) == 42);
    assert(ok!(string, RCAbort)(42).andThen!(() => err!(int, RCAbort)("foo")).error == "foo");
    assertThrown!Throwable(err!(int, RCAbort)("foo").orElse!(() => ok!(string, RCAbort)(42)));
    assertThrown!Throwable(ok!(string, RCAbort)(42).andThen!(() => err!(int, RCAbort)("foo")));
}

/++ An exception that represents an error value.

    This is used by $(LREF Throw) hook when undefined value or error is
    accessed on $(LREF Expected)
+/
class Unexpected(T) : Exception
{
    // remove possible inout qualifier
    static if (is(T U == inout U)) alias ET = U;
    else alias ET = T;

    ET error; /// error value

    /// Constructs an `Unexpected` exception from an error value.
    pure @safe @nogc nothrow
    this()(auto ref T value, string file = __FILE__, size_t line = __LINE__)
    {
        import std.traits : isAssignable;
        static if (isAssignable!(string, T)) super(value, file, line);
        else super("Unexpected error", file, line);

        this.error = error;
    }
}

/++
    Creates an $(LREF Expected) object from an expected value, with type inference.
+/
Expected!(T, E, Hook) ok(E = string, Hook = Abort, T)(auto ref T value)
{
    return Expected!(T, E, Hook)(value);
}

/// ditto
Expected!(void, E, Hook) ok(E = string, Hook = Abort)()
{
    return Expected!(void, E, Hook)();
}

///
@("Expected from value")
unittest
{
    // void
    {
        auto res = ok();
        static assert(is(typeof(res) == Expected!(void, string)));
        assert(res);
    }

    // int
    {
        auto res = ok(42);
        static assert(is(typeof(res) == Expected!(int, string)));
        assert(res);
        assert(res.value == 42);
    }

    // string
    {
        auto res = ok("42");
        static assert(is(typeof(res) == Expected!(string, string)));
        assert(res);
        assert(res.value == "42");
    }

    // other error type
    {
        auto res = ok!bool(42);
        static assert(is(typeof(res) == Expected!(int, bool)));
        assert(res);
        assert(res.value == 42);
    }
}

/++ Constructs $(LREF Expected) from the result of the provided function.

    If the function is `nothrow`, it just returns it's result using $(LREF Expected).

    If not, then it consumes it's possible $(D Exception) using `try catch` block and
    constructs $(LREF Expected) in regards of the result.
+/
template consume(alias fun, Hook = Abort)
{
    auto consume(Args...)(auto ref Args args) if (is(typeof(fun(args))))
    {
        import std.traits : hasFunctionAttributes;

        alias T = typeof(fun(args));
        static if (is(hasFunctionAttributes!(fun, "nothrow"))) return ok!Exception(fun(args));
        else
        {
            try return Expected!(T, Exception)(fun(args));
            catch (Exception ex) return err!T(ex);
        }
    }
}

///
@("consume from function call")
unittest
{
    auto fn(int v) { if (v == 42) throw new Exception("don't panic"); return v; }

    assert(consume!fn(1) == 1);
    assert(consume!fn(42).error.msg == "don't panic");
}

/++
    Creates an $(LREF Expected) object from an error value, with type inference.
+/
Expected!(T, E, Hook) err(T = void, Hook = Abort, E)(auto ref E err)
{
    static if (Expected!(T, E, Hook).Types.length == 1 && !is(T == void))
        return Expected!(T, E, Hook)(err, false);
    else return Expected!(T, E, Hook)(err);
}

///
@("Expected from error value")
unittest
{
    // implicit void value type
    {
        auto res = err("foo");
        static assert(is(typeof(res) == Expected!(void, string)));
        assert(!res);
        assert(res.error == "foo");
    }

    // bool
    {
        auto res = err!int("42");
        static assert(is(typeof(res) == Expected!(int, string)));
        assert(!res);
        assert(res.error == "42");
    }

    // other error type
    {
        auto res = err!bool(42);
        static assert(is(typeof(res) == Expected!(bool, int)));
        assert(!res);
        assert(res.error == 42);
    }
}

/++
    Returns the error contained within the $(LREF Expected) _and then_ another value if there's no error.
    This function can be used for control flow based on $(LREF Expected) values.

    Params:
        exp = The $(LREF Expected) to call andThen on
        value = The value to return if there isn't an error
        pred = The predicate to call if the there isn't an error
+/
auto ref EX andThen(EX)(auto ref EX exp, auto ref EX value)
    if (is(EX : Expected!(T, E, H), T, E, H))
{
    return exp.hasError ? exp : value;
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
@("andThen")
unittest
{
    assert(ok(42).andThen(ok(1)) == 1);
    assert(ok(42).andThen!(() => ok(0)) == 0);
    assert(ok(42).andThen(err!int("foo")).error == "foo");
    assert(ok(42).andThen!(() => err!int("foo")).error == "foo");
    assert(err!int("foo").andThen(ok(42)).error == "foo");
    assert(err!int("foo").andThen!(() => ok(42)).error == "foo");
    assert(err!int("foo").andThen(err!int("bar")).error == "foo");
    assert(err!int("foo").andThen!(() => err!int("bar")).error == "foo");

    // with void value
    assert(ok().andThen!(() => ok()));
    assert(ok().andThen!(() => err("foo")).error == "foo");
    assert(err("foo").andThen!(() => ok()).error == "foo");
}

/++
    Returns the value contained within the $(LREF Expected) _or else_ another value if there's an error.
    This function can be used for control flow based on $(LREF Expected) values.

    Params:
        exp = The $(LREF Expected) to call orElse on
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
@("orElse")
unittest
{
    assert(ok(42).orElse(0) == 42);
    assert(ok(42).orElse!(() => 0) == 42);
    assert(err!int("foo").orElse(0) == 0);
    assert(err!int("foo").orElse!(() => 0) == 0);
    assert(ok(42).orElse!(() => ok(0)) == 42);
    assert(err!int("foo").orElse!(() => ok(42)) == 42);
    assert(err!int("foo").orElse!(() => err!int("bar")).error == "bar");

    // with void value
    assert(ok().orElse!(() => err("foo")));
    assert(err("foo").orElse!(() => ok()));
    assert(err("foo").orElse!(() => err("bar")).error == "bar");
}

/++
    Applies a function to the expected value in an $(LREF Expected) object.

    If no expected value is present, the original error value is passed through
    unchanged, and the function is not called.

    Params:
        op = function called to map $(LREF Expected) value
        hook = use another hook for mapped $(LREF Expected)

    Returns:
        A new $(LREF Expected) object containing the result.
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

        if (self.hasError) return err!(U, Hook)(self.error);
        else
        {
            static if (is(T == void)) return ok!(E, Hook)(op());
            else return ok!(E, Hook)(op(self.value));
        }
    }
}

///
@("map")
unittest
{
    {
        assert(ok(42).map!(a => a/2).value == 21);
        assert(ok().map!(() => 42).value == 42);
        assert(err!int("foo").map!(a => 42).error == "foo");
        assert(err("foo").map!(() => 42).error == "foo");
    }

    // remap hook
    {
        static struct Hook {}
        auto res = ok(42).map!(a => a/2, Hook);
        assert(res == 21);
        static assert(is(typeof(res) == Expected!(int, string, Hook)));
    }
}

/++
    Applies a function to the expected error in an $(LREF Expected) object.

    If no error is present, the original value is passed through
    unchanged, and the function is not called.

    Params:
        op = function called to map $(LREF Expected) error
        hook = use another hook for mapped $(LREF Expected)

    Returns:
        A new $(LREF Expected) object containing the result.
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
            if (self.hasValue) return ok!(U, Hook)(self.value);
        }
        return err!(T, Hook)(op(self.error));
    }
}

///
@("mapError")
unittest
{
    {
        assert(ok(42).mapError!(e => e).value == 42);
        assert(err("foo").mapError!(e => 42).error == 42);
        assert(err("foo").mapError!(e => new Exception(e)).error.msg == "foo");
    }

    // remap hook
    {
        static struct Hook {}
        auto res = ok(42).mapError!(e => e, Hook);
        assert(res == 42);
        static assert(is(typeof(res) == Expected!(int, string, Hook)));

        auto res2 = err!int("foo").mapError!(e => "bar", Hook);
        assert(res2.error == "bar");
        static assert(is(typeof(res2) == Expected!(int, string, Hook)));
    }
}

/++
    Maps a `Expected<T, E>` to `U` by applying a function to a contained value, or a fallback function to a contained error value.

    Both functions has to be of the same return type.

    This function can be used to unpack a successful result while handling an error.

    Params:
        valueOp = function called to map $(LREF Expected) value
        errorOp = function called to map $(LREF Expected) error
        hook = use another hook for mapped $(LREF Expected)

    Returns:
        A new $(LREF Expected) object containing the result.
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

///
@("mapOrElse")
unittest
{
    assert(ok(42).mapOrElse!(v => v/2, e => 0) == 21);
    assert(ok().mapOrElse!(() => true, e => false));
    assert(err!int("foo").mapOrElse!(v => v/2, e => 42) == 42);
    assert(!err("foo").mapOrElse!(() => true, e => false));
}
