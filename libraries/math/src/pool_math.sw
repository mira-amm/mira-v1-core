library;

use std::u128::U128;
use std::{math::*, primitive_conversions::u64::*};
use interfaces::errors::TransactionError;

const ONE_E_9: u64 = 1_000_000_000;
const PRECISION: u64 = 1_000_000_000;
const FEE_DENOMINATOR: u64 = 1_000_000;
const SCALE = 1_000_000_000; // 1e9
const ONE = 1;
const BASIS_POINTS: u64 = 10_000;

/// Subtracts the provided fee from amount
fn subtract_fee_from_amount(amount: u64, liquidity_miner_fee: u64) -> u64 {
    let fee = max(1, (amount * liquidity_miner_fee) / BASIS_POINTS);
    amount - fee
}

pub fn add_fee_to_amount(amount: u64, fee: u64) -> u64 {
    if (fee > 0) {
        let numerator = U128::from((0, amount)) * U128::from((0, PRECISION));
        let denominator = U128::from((0, PRECISION)) - U128::from((0, fee));
        let result_wrapped = (numerator / denominator).as_u64();

        result_wrapped.unwrap()
    } else {
        amount
    }
}

// TODO: duplication of the function above
pub fn remove_fee_from_amount(amount: u64, fee: u64) -> u64 {
    if (fee > 0) {
        let fee = amount * fee / FEE_DENOMINATOR;
        amount - u64::try_from(fee).unwrap()
    } else {
        amount
    }
}

/// Returns the maximum required amount of the input asset to get exactly `output_amount` of the output asset.
///
/// # Arguments
///
/// * `output_amount`: [u64] - The desired amount of the output asset.
/// * `input_reserve`: [u64] - The reserved amount of the input asset.
/// * `output_reserve`: [u64] - The reserved amount of the output asset.
/// * `liquidity_miner_fee`: [u64] - The fee paid to the liquidity miner.
///
/// # Returns
///
/// * [u64] - The maximum required amount of the input asset.
///
/// # Reverts
///
/// * When `input_reserve` isn't greater than 0 or `output_reserve` isn't greater than 0.
/// * When the internal math overflows.
pub fn maximum_input_for_exact_output(
    output_amount: u64,
    input_reserve: u64,
    output_reserve: u64,
    liquidity_miner_fee: u64,
) -> u64 {
    require(input_reserve > 0 && output_reserve > 0, TransactionError::InsufficientReserves);
    let numerator = U128::from((0, input_reserve)) * U128::from((0, output_amount));
    let denominator = U128::from((
        0,
        // TODO: looks like fee should be substracted from `result_wrapped`, not here. Check it
        subtract_fee_from_amount(output_reserve - output_amount, liquidity_miner_fee),
    ));
    let result_wrapped = (numerator / denominator).as_u64();

    if denominator > numerator {
        // TODO: check if that's correct. Shouldn't we rather take 1 here? More, than actually needed
        // 0 < result < 1, round the result down since there are no floating points.
        0
    } else {
        result_wrapped.unwrap() + 1
    }
}

/// Given exactly `input_amount` of the input asset, returns the minimum resulting amount of the output asset.
///
/// # Arguments
///
/// * `input_amount`: [u64] - The desired amount of the input asset.
/// * `input_reserve`: [u64] - The reserved amount of the input asset.
/// * `output_reserve`: [u64] - The reserved amount of the output asset.
/// * `liquidity_miner_fee`: [u64] - The fee paid to the liquidity miner.
///
/// # Returns
///
/// * [u64] - The minimum resulting amount of the output asset.
///
/// # Reverts
///
/// * When `input_reserve` isn't greater than 0 or `output_reserve` isn't greater than 0.
/// * When the internal math overflows.
pub fn minimum_output_given_exact_input(
    input_amount: u64,
    input_reserve: u64,
    output_reserve: u64,
    liquidity_miner_fee: u64,
) -> u64 {
    require(input_reserve > 0 && output_reserve > 0, TransactionError::InsufficientReserves);
    // TODO: just call `subtract_fee_from_amount`?
    let fee_multiplier = BASIS_POINTS - liquidity_miner_fee;
    let input_amount_with_fee = input_amount.as_u256() * fee_multiplier.as_u256();
    let numerator = input_amount_with_fee * output_reserve.as_u256();
    let denominator = input_reserve.as_u256() + input_amount_with_fee;

    u64::try_from(numerator / denominator).unwrap()
}

/// Calculates d in the equation: a / b = c / d.
///
/// # Arguments
///
/// * `a`: [u64] - The value of a in the equation a / b = c / d.
/// * `b`: [u64] - The value of b in the equation a / b = c / d.
/// * `c`: [u64] - The value of c in the equation a / b = c / d.
///
/// # Returns
///
/// * [u64] - The value of d in the equation a / b = c / d.
///
/// # Reverts
///
/// * When the internal math overflows.
pub fn proportional_value(b: u64, c: u64, a: u64) -> u64 {
    let calculation = (U128::from((0, b)) * U128::from((0, c)));
    let result_wrapped = (calculation / U128::from((0, a))).as_u64();
    result_wrapped.unwrap()
}

pub fn initial_liquidity(deposit_a: u64, deposit_b: u64) -> u64 {
    let product = deposit_a.as_u256() * deposit_b.as_u256();
    u64::try_from(product.sqrt()).unwrap()
}

// Adapted from the Solidly/Velodrome code
// https://github.com/velodrome-finance/contracts/blob/9e5a5748c3e2bcef7016cc4194ce9758f880153f/contracts/Pool.sol#L475
pub fn _k(x: u64, y: u64, stable: bool) -> u64 {
    if (stable) {
        let _a = (x * y) / PRECISION;
        let _b = ((x * x) / PRECISION + (y * y) / PRECISION);
        _a * _b / PRECISION // x3y+y3x >= k
    } else {
        x * y // xy >= k
    }
}

/// Get LP value for stable curve: x^3*y + x*y^3
/// * `x_coin` - reserves of coin X.
/// * `x_scale` - 10 pow X coin decimals amount.
/// * `y_coin` - reserves of coin Y.
/// * `y_scale` - 10 pow Y coin decimals amount.
fn lp_value(x_coin: u64, x_scale: u64, y_coin: u64, y_scale: u64) -> u64 {
    let x_u128 = U128::from((0, x_coin));
    let y_u256 = U128::from((0, y_coin));
    let u128e9 = U128::from((0, ONE_E_9));

    let x_scale_u128 = U128::from((0, x_scale));
    let y_scale_u128 = U128::from((0, y_scale));

    let _x = (x_u128 * u128e9) / x_scale_u128;

    let _y = (y_u256 * u128e9) / y_scale_u128;

    let _a = (_x * _y);

    // ((_x * _x) / 1e18 + (_y * _y) / 1e18)
    let _b = (_x * _x) + (_y * _y);
    let result_wrapped = (_a * _b).as_u64();

    result_wrapped.unwrap()
}

/// Get coin amount out by passing amount in, returns amount out (we don't take fees into account here).
/// It probably would eat a lot of gas and better to do it offchain (on your frontend or whatever),
/// yet if no other way and need blockchain computation we left it here.
/// * `input_amount` - amount of coin to swap.
/// * `scale_in` - 10 pow by coin decimals you want to swap.
/// * `scale_out` - 10 pow by coin decimals you want to get.
/// * `reserve_in` - reserves of coin to swap input_amount.
/// * `reserve_out` - reserves of coin to get in exchange.
pub fn stable_coin_out(
    input_amount: u64,
    scale_in: u64,
    scale_out: u64,
    reserve_in: u64,
    reserve_out: u64,
) -> u64 {
    let u2561e8 = ONE_E_9;
    let input_amount_u256 = input_amount;
    let scale_in_u256 = scale_in;
    let scale_out_u256 = scale_out;

    let xy = lp_value(reserve_in, scale_in, reserve_out, scale_out);

    let reserve_in_u256 = (reserve_in * u2561e8) / scale_in_u256;
    let reserve_out_u256 = (reserve_out * u2561e8) / scale_out_u256;
    let amount_in = (input_amount_u256 * u2561e8) / scale_in_u256;

    let total_reserve = (amount_in + reserve_in_u256);
    let _y = _get_y(total_reserve, xy, reserve_out_u256);
    let y = reserve_out_u256 - _y;

    let r = (y * scale_out_u256) / u2561e8;

    u64::try_from(r).unwrap()
}

/// Get coin amount in by passing amount out, returns amount in (we don't take fees into account here).
/// It probably would eat a lot of gas and better to do it offchain (on your frontend or whatever),
/// yet if no other way and need blockchain computation we left it here.
/// * `output_amount` - amount of coin you want to get.
/// * `scale_in` - 10 pow by coin decimals you want to swap.
/// * `scale_out` - 10 pow by coin decimals you want to get.
/// * `reserve_in` - reserves of coin to swap.
/// * `reserve_out` - reserves of coin to get in exchange.
pub fn stable_coin_in(
    output_amount: u64,
    scale_out: u64,
    scale_in: u64,
    reserve_out: u64,
    reserve_in: u64,
) -> u64 {
    let u2561e8 = ONE_E_9;

    let xy = lp_value(reserve_in, scale_in, reserve_out, scale_out);

    let reserve_in_u256 = (reserve_in * u2561e8) / scale_in;
    let reserve_out_u256 = (reserve_out * u2561e8) / scale_out;
    let amount_out = (output_amount * u2561e8) / scale_out;

    let total_reserve = reserve_out_u256 - amount_out;
    let y = _get_y(total_reserve, xy, reserve_in_u256);
    let x = y - reserve_out_u256;

    let r = (x * scale_in) / u2561e8;

    u64::try_from(r).unwrap()
}

/// Implements x0*y^3 + x0^3*y = x0*(y*y/1e18*y/1e18)/1e18+(x0*x0/1e18*x0/1e18)*y/1e18
fn _f(x0_u256: u64, y_u256: u64) -> u64 {
    // x0*(y*y/1e18*y/1e18)/1e18
    let yy = (y_u256 * y_u256);
    let yyy = (yy * y_u256);

    let a = (x0_u256 * yyy);

    //(x0*x0/1e18*x0/1e18)*y/1e18
    let xx = (x0_u256 * x0_u256);
    let xxx = (xx * x0_u256);
    let b = (xxx * y_u256);

    // a + b
    (a + b)
}

/// Implements 3 * x0 * y^2 + x0^3 = 3 * x0 * (y * y / 1e8) / 1e8 + (x0 * x0 / 1e8 * x0) / 1e8
fn _d(x0_u256: u64, y_u256: u64) -> u64 {
    let three_u256 = (3);

    // 3 * x0 * (y * y / 1e8) / 1e8
    let x3 = (three_u256 * x0_u256);
    let yy = (y_u256 * y_u256);
    let xyy3 = (x3 * yy);
    let xx = (x0_u256 * x0_u256);

    // x0 * x0 / 1e8 * x0 / 1e8
    let xxx = (xx * x0_u256);
    (xyy3 + xxx)
}

/// Trying to find suitable `y` value.
/// * `x0` - total reserve x (include `coin_in`) with transformed decimals.
/// * `xy` - lp value (see `lp_value` func).
/// * `y` - reserves out with transformed decimals.
fn _get_y(x0: u64, xy: u64, y: u64) -> u64 {
    let mut _y = y;

    let one_u256: u64 = 1;

    let mut i = 0;
    while (i < 255) {
        // let y_prev = _y;
        let k = _f(x0, _y);

        let mut _dy = 0;

        if k < xy {
            _dy = ((xy - k) / _d(x0, y)) + one_u256;
            _y = _y + _dy;
        } else {
            _dy = (k - xy) / _d(x0, y);
            _y = _y - _dy;
        }

        if (_dy < ONE || _dy == ONE) {
            return _y;
        }

        i = i + 1;
    }

    _y
}

/// Returns the maximum of two provided values
pub fn max(a: u64, b: u64) -> u64 {
    if (a > b) {
        a
    } else {
        b
    }
}
