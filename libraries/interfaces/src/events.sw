library;

use ::data_structures::{Asset, AssetPair, PoolId};

/// The information logged when a pool is registered.
pub struct RegisterPoolEvent {
    /// The pair of asset identifiers that make up the pool.
    pub pool_id: PoolId,
}

/// The information logged when liquidity is added.
pub struct AddLiquidityEvent {
    /// Identifiers and amounts of assets added to reserves.
    pub added_assets: AssetPair,
    /// Identifier and amount of liquidity pool assets minted and transferred to sender.
    pub liquidity: Asset,
}

/// The information logged when a deposit is made.
pub struct DepositEvent {
    /// Pool identifier that the deposited asset is added to.
    pub pool_id: PoolId,
    /// Deposited asset that may be withdrawn or used to add liquidity.
    pub deposited_asset: Asset,
    /// New deposit balance of asset in contract.
    pub new_balance: u64,
}

/// The information logged when liquidity is removed.
pub struct RemoveLiquidityEvent {
    /// Pool identifier that the liquidity is removed from.
    pub pool_id: PoolId,
    /// Identifiers and amounts of assets removed from reserves and transferred to sender.
    pub removed_reserve: AssetPair,
    /// Identifier and amount of burned liquidity pool assets.
    pub burned_liquidity: Asset,
}

/// The information logged when an asset swap is made.
pub struct SwapEvent {
    /// Identifier and amount of sold asset.
    pub input: Asset,
    /// Identifier and amount of bought asset.
    pub output: Asset,
}

/// The information logged when a withdraw is made.
pub struct WithdrawEvent {
    /// Pool identifier that the withdrawn asset is removed from.
    pub pool_id: PoolId,
    /// Identifier and amount of withdrawn asset.
    pub withdrawn_asset: Asset,
    /// Remaining deposit balance of asset in contract.
    pub remaining_balance: u64,
}
