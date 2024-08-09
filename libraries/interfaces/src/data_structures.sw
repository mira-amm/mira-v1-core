library;

/// (asset_0, asset_1, is_stable)
pub type PoolId = (AssetId, AssetId, bool);

pub struct Asset {
    pub id: AssetId,
    pub amount: u64,
}

impl Asset {
    pub fn new(id: AssetId, amount: u64) -> Self {
        Self { id, amount }
    }
}

pub struct PoolInfo {
    pub id: PoolId,
    pub reserve_0: u64,
    pub reserve_1: u64,
    pub decimals_0: u8,
    pub decimals_1: u8,
}

impl PoolInfo {
    pub fn new(
        id: PoolId,
        decimals_0: u8,
        decimals_1: u8,
    ) -> Self {
        Self {
            id,
            reserve_0: 0,
            reserve_1: 0,
            decimals_0,
            decimals_1,
        }
    }

    pub fn copy_with_reserves(self, reserve_0: u64, reserve_1: u64) -> PoolInfo {
        Self {
            id: self.id,
            reserve_0,
            reserve_1,
            decimals_0: self.decimals_0,
            decimals_1: self.decimals_1,
        }
    }
}

pub struct PoolInfoView {
    pub reserve_0: u64,
    pub reserve_1: u64,
    pub liquidity: u64, // TODO: make it Asset
    pub decimals_0: u8,
    pub decimals_1: u8,
}

impl PoolInfoView {
    pub fn from_pool_and_liquidity(
        pool: PoolInfo,
        liquidity: u64,
    ) -> Self {
        Self {
            reserve_0: pool.reserve_0,
            reserve_1: pool.reserve_1,
            liquidity: liquidity,
            decimals_0: pool.decimals_0,
            decimals_1: pool.decimals_1,
        }
    }
}
