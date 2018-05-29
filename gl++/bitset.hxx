#pragma once

template <typename Self, typename Underlying>
struct Bitset {
	typedef Bitset<Self, Underlying> Base;

	Bitset() = default;
	Bitset(Bitset const &) = default;
	~Bitset() = default;

protected:
	static Base atom(Underlying _value) {
		Base b;
		b.value = _value;
		return b;
	}

private:
	Underlying value;
};
