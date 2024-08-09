contract;

use std::{
    asset::{
        burn,
        mint,
        mint_to,
        transfer,
    },
    call_frames::msg_asset_id,
    constants::ZERO_B256,
    context::{this_balance, msg_amount},
    hash::*,
    math::*,
    storage::storage_string::*,
    storage::storage_vec::*,
    string::String,
};
use standards::src20::SRC20;
use utils::utils::{validate_pool_id, get_lp_asset, build_lp_name};
use utils::src20_utils::get_symbol_and_decimals;
use math::pool_math::{proportional_value, initial_liquidity, min, validate_curve};
use interfaces::mira_amm::MiraAMM;
use interfaces::data_structures::{
    Asset,
    AssetPair,
    PoolId,
    PoolInfo,
    RemoveLiquidityInfo,
    PoolInfoView,
};
use interfaces::errors::{InputError, AmmError};
use interfaces::events::{RegisterPoolEvent, SwapEvent, MintEvent, BurnEvent};

configurable {
    LIQUIDITY_MINER_FEE: u64 = 33, // 0,33%
    MINIMUM_LIQUIDITY: u64 = 100,
    LP_TOKEN_DECIMALS: u8 = 9,
}

storage {
    /// Pools storage
    pools: StorageMap<PoolId, PoolInfo> = StorageMap {},
    pool_ids: StorageVec<PoolId> = StorageVec {},
    /// Total reserves of specific assets across all pools
    total_reserves: StorageMap<AssetId, u64> = StorageMap {},

    /// The total supply of coins for a specific asset minted by this contract.
    lp_total_supply: StorageMap<AssetId, u64> = StorageMap {},
    /// The name of a specific asset minted by this contract.
    lp_name: StorageMap<AssetId, StorageString> = StorageMap {},
}

#[storage(read)]
fn get_pool(pool_id: PoolId) -> PoolInfo {
    validate_pool_id(pool_id);
    match storage.pools.get(pool_id).try_read() {
        Some(pool) => pool,
        None => {
            require(false, InputError::PoolDoesNotExist(pool_id));
            revert(0)
        },
    }
}

#[storage(read)]
fn get_total_reserve(asset_id: AssetId) -> u64 {
    storage.total_reserves.get(asset_id).try_read().unwrap_or(0)
}

#[storage(write)]
fn update_total_reserve(asset_id: AssetId) {
    storage.total_reserves.insert(asset_id, this_balance(asset_id));
}

#[storage(write)]
fn update_total_reserves(pool_id: PoolId) {
    update_total_reserve(pool_id.0);
    update_total_reserve(pool_id.1);
}

#[storage(read)]
fn get_lp_total_supply(asset_id: AssetId) -> Option<u64> {
    storage.lp_total_supply.get(asset_id).try_read()
}

#[storage(read)]
fn lp_asset_exists(asset: AssetId) -> bool {
    storage.lp_name.get(asset).try_read().is_some()
}

#[storage(read, write)]
fn initialize_pool(pool_id: PoolId, is_stable: bool, a_decimals: u8, b_decimals: u8, a_symbol: String, b_symbol: String) {
    require(storage.pools.get(pool_id).try_read().is_none(), InputError::PoolAlreadyExists(pool_id));
    let (_, pool_lp_asset) = get_lp_asset(pool_id);
    let lp_name = build_lp_name(a_symbol, b_symbol);

    let pool_info = PoolInfo::new(pool_id, a_decimals, b_decimals, is_stable);

    storage.pools.insert(pool_id, pool_info);
    storage.pool_ids.push(pool_id);
    storage.lp_name.get(pool_lp_asset).write_slice(lp_name);
    storage.lp_total_supply.insert(pool_lp_asset, 0);

    log(RegisterPoolEvent {
        pool_id: pool_id,
    });
}

#[storage(read, write)]
fn mint_lp_asset(pool_id: PoolId, to: Identity, amount: u64) -> Asset {
    let (pool_lp_asset_sub_id, pool_lp_asset) = get_lp_asset(pool_id);
    // must be present in the storage
    let lp_total_supply = get_lp_total_supply(pool_lp_asset).unwrap();
    storage
        .lp_total_supply
        .insert(pool_lp_asset, lp_total_supply + amount);
    mint_to(to, pool_lp_asset_sub_id, amount);
    Asset::new(pool_lp_asset, amount)
}

/// Burns the provided amount of LP token. Returns the initial total supply, prior the burn operation
#[storage(read, write)]
fn burn_lp_asset(pool_id: PoolId, burned_liquidity: Asset) -> u64 {
    let (pool_lp_asset_sub_id, pool_lp_asset) = get_lp_asset(pool_id);
    require(burned_liquidity.id == pool_lp_asset, InputError::InvalidAsset(burned_liquidity.id));
    require(burned_liquidity.amount > 0, InputError::ZeroInputAmount);

    // must be present in the storage
    let lp_total_supply = get_lp_total_supply(pool_lp_asset).unwrap();
    require(lp_total_supply >= burned_liquidity.amount, AmmError::InsufficientLiquidity);

    storage
        .lp_total_supply
        .insert(pool_lp_asset, lp_total_supply - burned_liquidity.amount);
    burn(pool_lp_asset_sub_id, burned_liquidity.amount);
    lp_total_supply
}


#[storage(read, write)]
fn transfer_out_assets(pool_id: PoolId, total_liquidity: u64, burned_liquidity: Asset, recepient: Identity) -> AssetPair {
    let mut pool = get_pool(pool_id);
    let removed_assets = AssetPair::new(
        Asset::new(pool_id.0, proportional_value(burned_liquidity.amount, pool.reserves.a.amount, total_liquidity)), 
        Asset::new(pool_id.1, proportional_value(burned_liquidity.amount, pool.reserves.b.amount, total_liquidity))
    );

    pool.reserves = pool.reserves - removed_assets;
    storage.pools.insert(pool_id, pool);

    transfer(recepient, removed_assets.a.id, removed_assets.a.amount);
    transfer(recepient, removed_assets.b.id, removed_assets.b.amount);

    removed_assets
}

#[storage(read)]
fn get_pool_liquidity(pool_id: PoolId) -> u64 {
    let (_, pool_lp_asset) = get_lp_asset(pool_id);
    // must be present in the storage
    get_lp_total_supply(pool_lp_asset).unwrap()
}

impl SRC20 for Contract {
    #[storage(read)]
    fn total_assets() -> u64 {
        storage.pool_ids.len()
    }
    #[storage(read)]
    fn total_supply(asset: AssetId) -> Option<u64> {
        get_lp_total_supply(asset)
    }
    #[storage(read)]
    fn name(asset: AssetId) -> Option<String> {
        storage.lp_name.get(asset).read_slice()
    }
    #[storage(read)]
    fn symbol(asset: AssetId) -> Option<String> {
        if lp_asset_exists(asset) {
            Some(String::from_ascii_str("MIRA-LP"))
        } else {
            None
        }
    }
    #[storage(read)]
    fn decimals(asset: AssetId) -> Option<u8> {
        if lp_asset_exists(asset) {
            Some(LP_TOKEN_DECIMALS)
        } else {
            None
        }
    }
}

impl MiraAMM for Contract {
    #[storage(read, write)]
    fn add_pool(
        token_a_contract_id: ContractId,
        token_a_sub_id: b256,
        token_b_contract_id: ContractId,
        token_b_sub_id: b256,
        is_stable: bool,
    ) {
        let token_a_id = AssetId::new(token_a_contract_id, token_a_sub_id);
        let token_b_id = AssetId::new(token_b_contract_id, token_b_sub_id);
        let pool_id = (token_a_id, token_b_id);
        validate_pool_id(pool_id);

        let (a_symbol, a_decimals) = get_symbol_and_decimals(token_a_contract_id, token_a_id);
        let (b_symbol, b_decimals) = get_symbol_and_decimals(token_b_contract_id, token_b_id);

        initialize_pool(pool_id, is_stable, a_decimals, b_decimals, a_symbol, b_symbol);
    }

    #[storage(read)]
    fn pool_info(pool_id: PoolId) -> PoolInfoView {
        let pool = get_pool(pool_id);
        let liquidity = get_pool_liquidity(pool_id);
        PoolInfoView::from_pool_and_liquidity(pool, liquidity)
    }

    #[storage(read)]
    fn pools() -> Vec<PoolId> {
        storage.pool_ids.load_vec()
    }

    #[storage(read, write)]
    fn mint(pool_id: PoolId, to: Identity) -> Asset {
        let mut pool = get_pool(pool_id);

        let total_reserve_0 = get_total_reserve(pool_id.0);
        let total_reserve_1 = get_total_reserve(pool_id.1);
        let balance_0 = this_balance(pool_id.0);
        let balance_1 = this_balance(pool_id.1);
        let amount_0 = balance_0 - total_reserve_0;
        let amount_1 = balance_1 - total_reserve_1;

        let mut total_liquidity = get_pool_liquidity(pool_id);

        let added_liquidity: u64 = if total_liquidity == 0 {
            initial_liquidity(amount_0, amount_1) // TODO:  - MINIMUM_LIQUIDITY
            // _mint(Identity::Address(Address::from(ZERO_B256)), MINIMUM_LIQUIDITY);
        } else {
            min(
                proportional_value(amount_0, total_liquidity, pool.reserves.a.amount),
                proportional_value(amount_1, total_liquidity, pool.reserves.b.amount)
            )
        };
        require(added_liquidity > 0, AmmError::NoLiquidityAdded);

        let added_assets = AssetPair::new(Asset::new(pool_id.0, amount_0), Asset::new(pool_id.1, amount_1));
        pool.reserves = pool.reserves + added_assets;
        storage.pools.insert(pool_id, pool);
        update_total_reserves(pool_id);

        let minted = mint_lp_asset(pool_id, to, added_liquidity);
        log(MintEvent { pool_id, recipient: to, liquidity: minted, assets_in: added_assets });
        minted
    }

    #[payable]
    #[storage(read, write)]
    fn burn(pool_id: PoolId, to: Identity) -> AssetPair {
        validate_pool_id(pool_id);

        let burned_liquidity = Asset::new(msg_asset_id(), msg_amount());
        let total_liquidity = burn_lp_asset(pool_id, burned_liquidity);
        let removed_assets = transfer_out_assets(pool_id, total_liquidity, burned_liquidity, to);

        update_total_reserves(pool_id);

        log(BurnEvent { pool_id, recipient: to, liquidity: burned_liquidity, assets_out: removed_assets });
        
        removed_assets
    }

    #[payable]
    #[storage(read, write)]
    fn swap(pool_id: PoolId, amount_0_out: u64, amount_1_out: u64, to: Identity) {
        let mut pool = get_pool(pool_id);
        require(amount_0_out > 0 || amount_1_out > 0, InputError::ZeroOutputAmount);
        require(amount_0_out < pool.reserves.a.amount && amount_1_out < pool.reserves.b.amount, AmmError::InsufficientLiquidity);
        // Optimistically transfer assets
        if (amount_0_out > 0) {
            transfer(to, pool_id.0, amount_0_out);
        }
        if (amount_1_out > 0) {
            transfer(to, pool_id.1, amount_1_out);
        }
        // TODO: flash loans logic

        let total_reserve_0 = get_total_reserve(pool_id.0);
        let total_reserve_1 = get_total_reserve(pool_id.1);
        let balance_0 = this_balance(pool_id.0);
        let balance_1 = this_balance(pool_id.1);
        let amount_0_in = if balance_0 > total_reserve_0 - amount_0_out {
            balance_0 - (total_reserve_0 - amount_0_out)
        } else {
            0
        };
        let amount_1_in = if balance_1 > total_reserve_1 - amount_1_out {
            balance_1 - (total_reserve_1 - amount_1_out)
        } else {
            0
        };
        require(amount_0_in > 0 || amount_1_in > 0, InputError::ZeroInputAmount);

        validate_curve(pool.is_stable, balance_0, balance_1, pool.reserves.a.amount, pool.reserves.b.amount, pool.decimals_a, pool.decimals_b);
        // TODO: Update all reserves
        // pool.reserves = pool.reserves.a.amount + added_assets;
        // storage.pools.insert(pool_id, pool);

        update_total_reserves(pool_id);

        // log(SwapEvent{ pool_id, recipient: to, amount_0_in, amount_1_in, amount_0_out, amount_1_out });
    }
}
