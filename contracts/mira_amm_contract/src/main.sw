contract;

use std::{
    asset::{
        burn,
        mint,
        mint_to,
        transfer,
    },
    auth::msg_sender,
    block::height,
    call_frames::msg_asset_id,
    constants::ZERO_B256,
    context::msg_amount,
    hash::*,
    math::*,
    storage::storage_string::*,
    string::String,
};
use standards::src20::SRC20;
use utils::utils::{send_asset_pair, validate_pool_id, get_lp_asset, check_deadline, build_lp_name, determine_assets};
use math::pool_math::{
    add_fee_to_amount,
    remove_fee_from_amount,
    stable_coin_in,
    stable_coin_out,
    maximum_input_for_exact_output, minimum_output_given_exact_input, proportional_value, initial_liquidity
};
use interfaces::mira_amm::MiraAMM;
use interfaces::data_structures::{
    Asset,
    AssetPair,
    PoolId,
    PoolInfo,
    RemoveLiquidityInfo,
    PoolInfoView,
};
use interfaces::errors::{PoolManagementError, InputError, TransactionError};
use interfaces::events::{
    AddLiquidityEvent,
    DepositEvent,
    RegisterPoolEvent,
    RemoveLiquidityEvent,
    SwapEvent,
    WithdrawEvent,
};

configurable {
    LIQUIDITY_MINER_FEE: u64 = 33, // 0,33%
    MINIMUM_LIQUIDITY: u64 = 100,
    LP_TOKEN_DECIMALS: u8 = 9,
}

storage {
    // Pools storage
    pools: StorageMap<PoolId, PoolInfo> = StorageMap {},
    deposits: StorageMap<PoolId, StorageMap<(Identity, AssetId), u64>> = StorageMap {},
    // LP token storage
    lp_total_assets: u64 = 0,
    // TODO: remove `liquidity` from the PoolInfo, since we have it here as `total_supply`
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
            require(false, PoolManagementError::PoolDoesNotExist);
            revert(0)
        },
    }
}

#[storage(read)]
fn lp_asset_exists(asset: AssetId) -> bool {
    storage.lp_name.get(asset).try_read().is_some()
}

#[storage(read, write)]
fn initialize_pool(pool_id: PoolId, pool_info: PoolInfo, token_a_symbol: String, token_b_symbol: String) {
    let (_, pool_lp_asset) = get_lp_asset(pool_id);
    let lp_name = build_lp_name(token_a_symbol, token_b_symbol);

    storage.pools.insert(pool_id, pool_info);
    storage.deposits.insert(pool_id, StorageMap {});
    storage.lp_name.get(pool_lp_asset).write_slice(lp_name);
    storage
        .lp_total_assets
        .write(storage.lp_total_assets.read() + 1);
    storage
        .lp_total_supply
        .insert(pool_lp_asset, 0);

    log(RegisterPoolEvent {
        pool_id: pool_id,
    });
}

#[storage(read)]
fn get_deposit(pool_id: PoolId, asset_id: AssetId, user: Identity) -> u64 {
    storage.deposits.get(pool_id).get((user, asset_id)).try_read().unwrap_or(0)
}

#[storage(read, write)]
fn mint_lp_asset(pool_id: PoolId, to: Identity, amount: u64) -> Asset {
    let (pool_lp_asset_sub_id, pool_lp_asset) = get_lp_asset(pool_id);
    // must be present in the storage
    let lp_total_supply = storage.lp_total_supply.get(pool_lp_asset).try_read().unwrap();
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
    require(burned_liquidity.amount > 0, InputError::ExpectedNonZeroAmount(burned_liquidity.id));

    // must be present in the storage
    let lp_total_supply = storage.lp_total_supply.get(pool_lp_asset).try_read().unwrap();
    require(lp_total_supply >= burned_liquidity.amount, TransactionError::InsufficientLiquidity);

    storage
        .lp_total_supply
        .insert(pool_lp_asset, lp_total_supply - burned_liquidity.amount);
    burn(pool_lp_asset_sub_id, burned_liquidity.amount);
    lp_total_supply
}

#[storage(read, write)]
fn reset_user_deposits(pool_id: PoolId, user: Identity) {
    storage
        .deposits
        .get(pool_id)
        .insert((user, pool_id.0), 0);
    storage
        .deposits
        .get(pool_id)
        .insert((user, pool_id.1), 0);
}

#[storage(read, write)]
fn transfer_out_assets(pool_id: PoolId, total_liquidity: u64, burned_liquidity: Asset, recepient: Identity) -> AssetPair {
    let mut pool = get_pool(pool_id);
    let mut removed_assets = AssetPair::new(Asset::new(pool.reserves.a.id, 0), Asset::new(pool.reserves.b.id, 0));
    removed_assets.a.amount = proportional_value(burned_liquidity.amount, pool.reserves.a.amount, total_liquidity);
    removed_assets.b.amount = proportional_value(burned_liquidity.amount, pool.reserves.b.amount, total_liquidity);

    pool.reserves = pool.reserves - removed_assets;
    storage.pools.insert(pool_id, pool);

    transfer(recepient, removed_assets.a.id, removed_assets.a.amount);
    transfer(recepient, removed_assets.b.id, removed_assets.b.amount);

    removed_assets
}

#[storage(read, write)]
fn swap(pool_id: PoolId, output: u64, deadline: u32, is_exact_input: bool) -> (u64, u64) {
    check_deadline(deadline);
    let mut pool = get_pool(pool_id);

    let (mut input_asset_reserve, mut output_asset_reserve) = determine_assets(msg_asset_id(), pool.reserves);
    let input_amount = msg_amount();
    require(input_amount > 0, InputError::ExpectedNonZeroAmount(input_asset_reserve.id));

    let sender = msg_sender().unwrap();

    let (asset_in, asset_out) = if (is_exact_input) {
        let mut bought = 0;
        if pool.is_stable {
            let input_with_fee = remove_fee_from_amount(input_amount, LIQUIDITY_MINER_FEE);
            let scale_in = 10u64.pow(pool.decimals_a.into());
            let scale_out = 10u64.pow(pool.decimals_b.into());

            bought = stable_coin_out(
                input_with_fee,
                scale_in,
                scale_out,
                input_asset_reserve.amount,
                output_asset_reserve.amount,
            );
        } else {
            bought = minimum_output_given_exact_input(
                input_amount,
                input_asset_reserve.amount,
                output_asset_reserve.amount,
                LIQUIDITY_MINER_FEE,
            );
        }
        require(bought > 0, TransactionError::DesiredAmountTooLow(input_amount));
        require(bought >= output, TransactionError::DesiredAmountTooHigh(output));
        (input_amount, bought)
    } else {
        require(output > 0, InputError::ExpectedNonZeroParameter(output_asset_reserve.id));
        require(
            output <= output_asset_reserve.amount,
            TransactionError::InsufficientReserve(output_asset_reserve.id),
        );

        let mut sold = 0;
        if pool.is_stable {
            let output_with_fee = add_fee_to_amount(output, LIQUIDITY_MINER_FEE);
            let scale_in = 10u64.pow(pool.decimals_a.into());
            let scale_out = 10u64.pow(pool.decimals_b.into());

            sold = stable_coin_in(
                output_with_fee,
                scale_out,
                scale_in,
                input_asset_reserve.amount,
                output_asset_reserve.amount,
            );
        } else {
            sold = maximum_input_for_exact_output(
                output,
                input_asset_reserve.amount,
                output_asset_reserve.amount,
                LIQUIDITY_MINER_FEE,
            );
        }

        require(sold > 0, TransactionError::DesiredAmountTooLow(output));
        require(input_amount >= sold, TransactionError::DesiredAmountTooHigh(input_amount));
        let refund = input_amount - sold;
        if refund > 0 {
            transfer(sender, input_asset_reserve.id, refund);
        }
        (sold, output)
    };

    // TODO: move to the top to enable flash loans?
    transfer(sender, output_asset_reserve.id, asset_out);

    input_asset_reserve.amount += asset_in;
    output_asset_reserve.amount -= asset_out;

    pool.reserves = AssetPair::new(input_asset_reserve, output_asset_reserve).sort(pool.reserves);
    storage.pools.insert(pool_id, pool);

    // TODO: add more info to the event: user, asset inputted, asset outputted
    log(SwapEvent {
        input: input_asset_reserve,
        output: output_asset_reserve,
    });

    (asset_in, asset_out)
}

#[storage(read)]
fn get_pool_liquidity(pool_id: PoolId) -> u64 {
    let (_, pool_lp_asset) = get_lp_asset(pool_id);
    storage.lp_total_supply.get(pool_lp_asset).try_read().unwrap_or(0)
}

impl SRC20 for Contract {
    #[storage(read)]
    fn total_assets() -> u64 {
        storage.lp_total_assets.read()
    }
    #[storage(read)]
    fn total_supply(asset: AssetId) -> Option<u64> {
        storage.lp_total_supply.get(asset).try_read()
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

        let pool = storage.pools.get(pool_id).try_read();
        require(pool.is_none(), PoolManagementError::PoolAlreadyExists);

        let token_a = abi(SRC20, token_a_contract_id.into());
        let token_b = abi(SRC20, token_b_contract_id.into());

        let token_a_symbol = token_a.symbol(token_a_id).unwrap_or(String::from_ascii_str("UNKNOWN"));
        let token_b_symbol = token_b.symbol(token_b_id).unwrap_or(String::from_ascii_str("UNKNOWN"));
        let token_a_decimals = token_a.decimals(token_a_id).unwrap_or(0);
        let token_b_decimals = token_b.decimals(token_b_id).unwrap_or(0);

        let pool_info = PoolInfo::new(
            pool_id,
            token_a_decimals,
            token_b_decimals,
            is_stable,
        );

        initialize_pool(pool_id, pool_info, token_a_symbol, token_b_symbol);
    }

    #[storage(read)]
    fn pool_info(pool_id: PoolId) -> PoolInfoView {
        let pool = get_pool(pool_id);
        let liquidity = get_pool_liquidity(pool_id);
        PoolInfoView::from_pool_and_liquidity(pool, liquidity)
    }

    #[storage(read, write)]
    fn add_liquidity(
        pool_id: PoolId,
        desired_liquidity: u64,
        deadline: u32,
    ) -> Asset {
        check_deadline(deadline);
        require(
            MINIMUM_LIQUIDITY <= desired_liquidity,
            InputError::CannotAddLessThanMinimumLiquidity(desired_liquidity),
        );

        let mut pool = get_pool(pool_id);

        let sender = msg_sender().unwrap();
        let reserves = pool.reserves;

        let deposits = AssetPair::new(
            Asset::new(pool_id.0, get_deposit(pool_id, pool_id.0, sender)),
            Asset::new(pool_id.1, get_deposit(pool_id, pool_id.1, sender)),
        );

        require(
            deposits.a.amount != 0,
            TransactionError::ExpectedNonZeroDeposit(deposits.a.id),
        );
        require(
            deposits.b.amount != 0,
            TransactionError::ExpectedNonZeroDeposit(deposits.b.id),
        );

        let mut total_liquidity = get_pool_liquidity(pool_id);
        let mut added_assets = AssetPair::new(Asset::new(reserves.a.id, 0), Asset::new(reserves.b.id, 0));
        let mut added_liquidity = 0;

        if reserves.a.amount == 0 && reserves.b.amount == 0 {
            // Adding liquidity for the first time.
            // Using all the deposited assets to determine the ratio.
            added_liquidity = initial_liquidity(deposits.a.amount, deposits.b.amount);
            added_assets.a.amount = deposits.a.amount;
            added_assets.b.amount = deposits.b.amount;
        } else {
            // Adding liquidity based on current ratio.
            // Attempting to add liquidity by using up all the deposited asset A amount.
            let b_to_attempt = proportional_value(deposits.a.amount, reserves.b.amount, reserves.a.amount);
            if b_to_attempt <= deposits.b.amount {
                // Deposited asset B amount is sufficient
                added_liquidity = proportional_value(b_to_attempt, total_liquidity, reserves.b.amount);
                added_assets.a.amount = deposits.a.amount;
                added_assets.b.amount = b_to_attempt;
            } // TODO: should here be the else clause? Should we stop calculations if we already defined that asset b amount is sufficient above?

            let a_to_attempt = proportional_value(deposits.b.amount, reserves.a.amount, reserves.b.amount);
            if a_to_attempt <= deposits.a.amount { // attempt to add liquidity by using up the deposited asset B amount.
                added_liquidity = proportional_value(a_to_attempt, total_liquidity, reserves.a.amount);
                added_assets.a.amount = a_to_attempt;
                added_assets.b.amount = deposits.b.amount;
            }
            send_asset_pair(sender, deposits - added_assets);
        }

        require(
            desired_liquidity <= added_liquidity,
            TransactionError::DesiredAmountTooHigh(desired_liquidity),
        );
        pool.reserves = reserves + added_assets;
        storage.pools.insert(pool_id, pool);

        let minted = mint_lp_asset(pool_id, sender, added_liquidity);
        reset_user_deposits(pool_id, sender);

        log(AddLiquidityEvent { added_assets, liquidity: minted });

        minted
    }

    // TODO: be consistent, rename to deposit_liquidity
    #[payable, storage(read, write)]
    fn deposit(pool_id: PoolId) {
        // check that pool exists
        let _ = get_pool(pool_id);

        let deposited_asset = msg_asset_id();
        let sender = msg_sender().unwrap();
        let amount = msg_amount();

        require(pool_id.0 == deposited_asset || pool_id.1 == deposited_asset, InputError::InvalidAsset(deposited_asset));

        let new_balance = get_deposit(pool_id, deposited_asset, sender) + amount;
        storage
            .deposits
            .get(pool_id)
            .insert((sender, deposited_asset), new_balance);

        log(DepositEvent {
            pool_id: pool_id,
            deposited_asset: Asset::new(deposited_asset, amount),
            new_balance,
        });
    }

    #[payable, storage(read, write)]
    fn remove_liquidity(
        pool_id: PoolId,
        min_asset_a: u64,
        min_asset_b: u64,
        deadline: u32,
    ) -> RemoveLiquidityInfo {
        validate_pool_id(pool_id);
        check_deadline(deadline);

        let burned_liquidity = Asset::new(msg_asset_id(), msg_amount());
        let total_liquidity = burn_lp_asset(pool_id, burned_liquidity);
        let removed_assets = transfer_out_assets(pool_id, total_liquidity, burned_liquidity, msg_sender().unwrap());

        require(removed_assets.a.amount >= min_asset_a, TransactionError::DesiredAmountTooHigh(min_asset_a));
        require(removed_assets.b.amount >= min_asset_b, TransactionError::DesiredAmountTooHigh(min_asset_b));

        log(RemoveLiquidityEvent {
            pool_id: pool_id,
            removed_reserve: removed_assets,
            burned_liquidity,
        });

        RemoveLiquidityInfo {
            removed_amounts: removed_assets,
            burned_liquidity,
        }
    }

    #[storage(read, write)]
    fn withdraw(pool_id: PoolId, asset: Asset) {
        // check that pool exists
        let _ = get_pool(pool_id);
        let sender = msg_sender().unwrap();
        let deposited_amount = get_deposit(pool_id, asset.id, sender);

        require(
            deposited_amount >= asset.amount,
            TransactionError::DesiredAmountTooHigh(asset.amount),
        );

        let new_amount = deposited_amount - asset.amount;
        // TODO: remove from the storage if new_amount = 0?
        storage
            .deposits
            .get(pool_id)
            .insert((sender, asset.id), new_amount);
        transfer(sender, asset.id, asset.amount);

        // TODO: add user to the event?
        log(WithdrawEvent {
            pool_id: pool_id,
            withdrawn_asset: asset,
            remaining_balance: new_amount,
        });
    }

    #[payable, storage(read, write)]
    fn swap_exact_input(pool_id: PoolId, min_output: u64, deadline: u32) -> u64 {
        let (_, bought) = swap(pool_id, min_output, deadline, true);
        bought
    }

    #[payable, storage(read, write)]
    fn swap_exact_output(pool_id: PoolId, output: u64, deadline: u32) -> u64 {
        let (sold, _) = swap(pool_id, output, deadline, false);
        sold
    }

    #[storage(read)]
    fn balance(pool_id: PoolId, asset_id: AssetId) -> u64 {
        // check that pool exists
        let _ = get_pool(pool_id);
        get_deposit(pool_id, asset_id, msg_sender().unwrap())
    }
}
