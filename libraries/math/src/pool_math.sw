library;

use std::{math::*, primitive_conversions::u64::*};
use interfaces::errors::AmmError;

const BASIS_POINTS: u64 = 10_000;
const ONE_E_18: u256 = 1_000_000_000_000_000_000;

pub fn proportional_value(b: u64, c: u64, a: u64) -> u64 {
    u64::try_from(b.as_u256() * c.as_u256() / a.as_u256()).unwrap()
}

pub fn initial_liquidity(deposit_a: u64, deposit_b: u64) -> u64 {
    let product = deposit_a.as_u256() * deposit_b.as_u256();
    u64::try_from(product.sqrt()).unwrap()
}

pub fn max(a: u64, b: u64) -> u64 {
    if a > b {
        a
    } else {
        b
    }
}

pub fn min(a: u64, b: u64) -> u64 {
    if a < b {
        a
    } else {
        b
    }
}

fn _k(is_stable: bool, x: u64, y: u64, decimals_x: u8, decimals_y: u8) -> u256 {
    if (is_stable) {
        let _x: u256 = x.as_u256() * ONE_E_18 / decimals_x.as_u256();
        let _y: u256 = y.as_u256() * ONE_E_18 / decimals_y.as_u256();
        let _a: u256 = (_x * _y) / ONE_E_18;
        let _b: u256 = ((_x * _x) / ONE_E_18 + (_y * _y) / ONE_E_18);
        return _a * _b / ONE_E_18;  // x3y+y3x >= k
    } else {
        return x.as_u256() * y.as_u256(); // xy >= k
    }
}

/// Validates the curve invariant, either x3y+y3x for stable pools, or x*y for volatile pools
pub fn validate_curve(is_stable: bool, balance_0: u64, balance_1: u64, reserve_0: u64, reserve_1: u64, decimals_0: u8, decimals_1: u8) {
    let reserves_k: u256 = _k(is_stable, reserve_0, reserve_1, decimals_0, decimals_1);
    let balances_k: u256 = _k(is_stable, balance_0, balance_1, decimals_0, decimals_1);
    require(balances_k >= reserves_k, AmmError::CurveInvariantViolation((balances_k, reserves_k)));
}
