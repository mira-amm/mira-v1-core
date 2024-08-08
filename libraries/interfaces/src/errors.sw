library;

/// Errors related to pools management.
pub enum PoolManagementError {
    /// The pool has already been created.
    PoolAlreadyExists: (),
    /// The pool doesn't exist.
    PoolDoesNotExist: (),
    /// Provided two identical assets.
    IdenticalAssets: (),
    UnsortedAssetPair: (),
}

/// Errors related to inputs.
pub enum InputError {
    /// The amount of liquidity added is less than the minimum amount.
    CannotAddLessThanMinimumLiquidity: u64,
    /// The deadline has passed.
    DeadlinePassed: u32,
    /// The input amount was not greater than zero.
    ExpectedNonZeroAmount: AssetId,
    /// The parameter was not greater than zero.
    ExpectedNonZeroParameter: AssetId,
    /// The provided asset id is invalid.
    InvalidAsset: AssetId,
}

/// Error related to transactions.
pub enum TransactionError {
    /// The desired amount is too high.
    DesiredAmountTooHigh: u64,
    /// The desired amount is too low.
    DesiredAmountTooLow: u64,
    /// The deposit amount was not greater than zero.
    ExpectedNonZeroDeposit: AssetId,
    /// The reserve amount is too low.
    InsufficientReserve: AssetId,
    /// The reserves are too low.
    InsufficientReserves: (),
    /// The total liquidity is too low.
    InsufficientLiquidity: (),
}
