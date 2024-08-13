use fuels::prelude::{
    Address, AssetId, Bech32Address, Contract, LoadConfiguration, Provider, StorageConfiguration,
    TxPolicies, WalletUnlocked,
};

pub mod common {
    use super::*;
    use fuels::test_helpers::{setup_multiple_assets_coins, setup_test_provider};

    use crate::{
        data_structures::{MiraAMMContract, WalletAssetConfiguration},
        interface::MiraAMM,
        paths::{AMM_CONTRACT_BINARY_PATH, AMM_STORAGE_PATH},
    };

    pub async fn deploy_amm(wallet: &WalletUnlocked) -> MiraAMMContract {
        let storage_configuration =
            StorageConfiguration::default().add_slot_overrides_from_file(AMM_STORAGE_PATH).unwrap();

        let configuration =
            LoadConfiguration::default().with_storage_configuration(storage_configuration);

        let contract_id = Contract::load_from(AMM_CONTRACT_BINARY_PATH, configuration)
            .unwrap()
            .deploy(wallet, TxPolicies::default())
            .await
            .unwrap();

        let instance = MiraAMM::new(contract_id.clone(), wallet.clone());

        MiraAMMContract { instance, id: contract_id.into() }
    }

    pub async fn deploy_and_initialize_amm(wallet: &WalletUnlocked) -> MiraAMMContract {
        let amm = deploy_amm(wallet).await;

        amm
    }

    pub async fn setup_wallet_and_provider(
        asset_parameters: &WalletAssetConfiguration,
    ) -> (WalletUnlocked, Vec<AssetId>, Provider) {
        let mut wallet = WalletUnlocked::new_random(None);

        let (coins, asset_ids) = setup_multiple_assets_coins(
            wallet.address(),
            asset_parameters.number_of_assets,
            asset_parameters.coins_per_asset,
            asset_parameters.amount_per_coin,
        );

        let provider = setup_test_provider(coins.clone(), vec![], None, None).await.unwrap();

        wallet.set_provider(provider.clone());

        (wallet, asset_ids, provider)
    }
}

pub mod scripts {
    use super::*;
    use crate::data_structures::TransactionParameters;

    use fuels::{
        prelude::ResourceFilter,
        types::{coin_type::CoinType, input::Input, output::Output},
    };

    pub const MAXIMUM_INPUT_AMOUNT: u64 = 1_000_000;

    async fn transaction_input_coin(
        provider: &Provider,
        from: &Bech32Address,
        asset_id: AssetId,
        amount: u64,
    ) -> Vec<Input> {
        let coins = &provider
            .get_spendable_resources(ResourceFilter {
                from: from.clone(),
                asset_id: Some(asset_id),
                amount,
                ..Default::default()
            })
            .await
            .unwrap();

        let input_coins: Vec<Input> = coins
            .iter()
            .map(|coin| match coin {
                CoinType::Coin(_) => Input::resource_signed(coin.clone()),
                _ => panic!("Coin type does not match"),
            })
            .collect();

        input_coins
    }

    fn transaction_output_variable() -> Output {
        Output::Variable { amount: 0, to: Address::zeroed(), asset_id: AssetId::default() }
    }

    pub async fn transaction_inputs_outputs(
        wallet: &WalletUnlocked,
        provider: &Provider,
        assets: &[AssetId],
        amounts: Option<&Vec<u64>>,
    ) -> TransactionParameters {
        let mut input_coins: Vec<Input> = vec![]; // capacity depends on wallet resources
        let mut output_variables: Vec<Output> = Vec::with_capacity(assets.len());

        for (asset_index, asset) in assets.iter().enumerate() {
            input_coins.extend(
                transaction_input_coin(
                    provider,
                    wallet.address(),
                    *asset,
                    if let Some(amounts_) = amounts {
                        *amounts_.get(asset_index).unwrap()
                    } else {
                        MAXIMUM_INPUT_AMOUNT
                    },
                )
                .await,
            );
            output_variables.push(transaction_output_variable());
        }

        TransactionParameters { inputs: input_coins, outputs: output_variables }
    }
}
