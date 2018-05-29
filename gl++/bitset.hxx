#pragma once

template <typename Self, typename Underlying>
struct Bitset {
	constexpr Bitset() = default;
	constexpr Bitset(Bitset const &) = default;
	constexpr Bitset& operator= (Bitset const &) = default;

	constexpr explicit Bitset(Underlying raw) : value(raw) {
	}

	constexpr explicit operator Underlying() const {
		return value;
	}

	constexpr operator Self() const {
		return Self{value};
	}

	constexpr explicit operator bool() const {
		return value;
	}

	constexpr bool operator== (Self const & b) const {
		return value == b.value;
	}

	constexpr bool operator!= (Self const & b) const {
		return value != b.value;
	}

	constexpr Self operator| (Self const &b) const {
		return Self{value | b.value};
	}

	constexpr Self operator& (Self const &b) const {
		return Self{value & b.value};
	}

	constexpr Self operator~ () const {
		return Self{~value};
	}

private:
	Underlying value;
};
