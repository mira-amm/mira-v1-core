library;

use ::data_structures::PoolId;

/// Errors related to transaction inputs.
pub enum InputError {
    /// The pool has already been created.
    PoolAlreadyExists: PoolId,
    /// The pool doesn't exist.
    PoolDoesNotExist: PoolId,
    /// The provided asset id is invalid.
    InvalidAsset: AssetId,
    /// The input amount is zero.
    ZeroInputAmount: (),
    /// The output amount is zero.
    ZeroOutputAmount: (),
    /// Provided two identical assets as pool id.
    IdenticalAssets: (),
    /// Provided unsorted asset pair as pool id.
    UnsortedAssetPair: (),
    /// Hash collision for LP token.
    LPTokenHashCollision: (),
}

/// Errors related to AMM logic.
pub enum AmmError {
    /// The pool liquidity is too low.
    InsufficientLiquidity: (),
    /// No liquidity added.
    NoLiquidityAdded: (),
    /// Curve invariant violation.
    CurveInvariantViolation: (u256, u256),
}
