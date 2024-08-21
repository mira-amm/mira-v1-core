use fuels::types::{AssetId, ContractId};

pub type PoolId = (AssetId, AssetId, bool, Option<ContractId>);
