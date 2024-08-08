library;

pub type PoolId = (AssetId, AssetId);

/// Information for a particular asset.
pub struct Asset {
    /// Identifier of asset.
    pub id: AssetId,
    /// Amount of asset that can represent reserve amount, deposit amount, withdraw amount and more depending on the context.
    pub amount: u64,
}

impl Asset {
    /// This function creates a new `Asset`.
    ///
    /// # Arguments
    ///
    /// * `id`: [AssetId] - The AssetId of the asset.
    /// * `amount`: [u64] - The amount of the asset.
    ///
    /// # Returns
    ///
    /// * `Asset` - The new asset.
    pub fn new(id: AssetId, amount: u64) -> Self {
        Self { id, amount }
    }
}

/// Information for a particular pair of assets.
pub struct AssetPair {
    /// One of the assets in the pair.
    pub a: Asset,
    /// One of the assets in the pair.
    pub b: Asset,
}

impl AssetPair {
    /// This function creates a new `AssetPair`.
    ///
    /// # Arguments
    ///
    /// * `a`: [Asset] - One of the assets in the pair.
    /// * `b`: [Asset] - One of the assets in the pair.
    ///
    /// # Returns
    ///
    /// * `AssetPair` - The new asset pair.
    pub fn new(a: Asset, b: Asset) -> Self {
        Self { a, b }
    }

    /// This function returns the Asset with the AssetId that matches `this_asset`.
    ///
    /// # Arguments
    ///
    /// * `this_asset`: [AssetId] - AssetId to match with.
    ///
    /// # Returns
    ///
    /// * `Asset` - The AssetId that matches `this_asset`.
    pub fn this_asset(self, this_asset: AssetId) -> Asset {
        if this_asset == self.a.id {
            self.a
        } else {
            self.b
        }
    }

    /// This function returns the Asset with the AssetId that does not match `this_asset`.
    ///
    /// # Arguments
    ///
    /// * `this_asset`: [AssetId] - AssetId to match with.
    ///
    /// # Returns
    ///
    /// * `Asset` - The AssetId that does not match `this_asset`.
    pub fn other_asset(self, this_asset: AssetId) -> Asset {
        if this_asset == self.a.id {
            self.b
        } else {
            self.a
        }
    }

    /// This function returns a new `AssetPair` with assets sorted based on the reserves.
    ///
    /// # Arguments
    ///
    /// * `reserves`: [Self] - The asset pair to sort by.
    ///
    /// # Returns
    ///
    /// * `AssetPair` - The new asset pair with assets sorted based on the reserves.
    pub fn sort(self, reserves: Self) -> Self {
        Self {
            a: if self.a.id == reserves.a.id {
                self.a
            } else {
                self.b
            },
            b: if self.a.id == reserves.a.id {
                self.b
            } else {
                self.a
            },
        }
    }
}

impl core::ops::Add for AssetPair {
    fn add(self, other: Self) -> Self {
        Self {
            a: Asset::new(self.a.id, self.a.amount + other.a.amount),
            b: Asset::new(self.b.id, self.b.amount + other.b.amount),
        }
    }
}

impl core::ops::Subtract for AssetPair {
    fn subtract(self, other: Self) -> Self {
        Self {
            a: Asset::new(self.a.id, self.a.amount - other.a.amount),
            b: Asset::new(self.b.id, self.b.amount - other.b.amount),
        }
    }
}

/// Information about the liquidity for a specific asset pair.
pub struct LiquidityParameters {
    /// The asset pair of the deposits.
    pub deposits: AssetPair,
    /// The amount of liquidity.
    pub liquidity: u64,
    /// The limit on block height for operation.
    pub deadline: u32,
}

/// Information about a specific pool.
pub struct PoolInfo {
    /// The unique identifiers and reserve amounts of the assets that make up the liquidity pool of the exchange contract.
    pub reserves: AssetPair,
    pub decimals_a: u8,
    pub decimals_b: u8,
    pub is_stable: bool,
}

impl PoolInfo {
    pub fn new(
        pool_id: PoolId,
        decimals_a: u8,
        decimals_b: u8,
        is_stable: bool,
    ) -> Self {
        Self {
            reserves: AssetPair::new(Asset::new(pool_id.0, 0), Asset::new(pool_id.1, 0)),
            decimals_a,
            decimals_b,
            is_stable,
        }
    }
}

/// Information about a specific pool.
pub struct PoolInfoView {
    /// The unique identifiers and reserve amounts of the assets that make up the liquidity pool of the exchange contract.
    pub reserves: AssetPair,
    /// The amount of liquidity pool asset supply in the exchange contract.
    pub liquidity: u64,
    pub decimals_a: u8,
    pub decimals_b: u8,
    pub is_stable: bool,
}

impl PoolInfoView {
    pub fn from_pool_and_liquidity(
        pool: PoolInfo,
        liquidity: u64,
    ) -> Self {
        Self {
            reserves: pool.reserves,
            liquidity: liquidity,
            decimals_a: pool.decimals_a,
            decimals_b: pool.decimals_b,
            is_stable: pool.is_stable,
        }
    }
}

/// Information regarding removing liquidity.
pub struct RemoveLiquidityInfo {
    /// Pool assets that are removed from the reserves and transferred to the sender.
    pub removed_amounts: AssetPair,
    /// The amount of liquidity that is burned.
    pub burned_liquidity: Asset,
}
