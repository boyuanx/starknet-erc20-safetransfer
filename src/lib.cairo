use starknet::ContractAddress;

/// Extended function selector as defined in SRC-5
const ISNIP88_RECEIVER_ID: felt252 =
    selector!("fn_on_erc20_received(ContractAddress,ContractAddress,u256,Span<felt252>)->felt252)");

#[starknet::interface]
trait ISNIP88Contract<TContractState> {
    fn safeTransferFrom(
        ref self: TContractState,
        sender: ContractAddress,
        recipient: ContractAddress,
        amount: u256,
        data: Span<felt252>
    );
    fn safe_transfer_from(
        ref self: TContractState,
        sender: ContractAddress,
        recipient: ContractAddress,
        amount: u256,
        data: Span<felt252>
    );
}

#[starknet::interface]
trait ISNIP88Receiver<TContractState> {
    fn on_erc20_received(
        self: @TContractState,
        operator: ContractAddress,
        from: ContractAddress,
        token_id: u256,
        data: Span<felt252>
    ) -> felt252;

    fn onERC20Received(
        self: @TContractState,
        operator: ContractAddress,
        from: ContractAddress,
        tokenId: u256,
        data: Span<felt252>
    ) -> felt252;
}

#[starknet::contract]
mod SafeTransferERC20 {
    use erc20_safetransfer::{
        ISNIP88Contract, ISNIP88ReceiverDispatcher, ISNIP88ReceiverDispatcherTrait,
        ISNIP88_RECEIVER_ID
    };
    use starknet::{ContractAddress, get_caller_address};
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use openzeppelin::introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
    use openzeppelin::account::interface::ISRC6_ID;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event
    }

    #[abi(embed_v0)]
    impl SNIP88Impl of super::ISNIP88Contract<ContractState> {
        fn safeTransferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
            data: Span<felt252>,
        ) {
            self.safe_transfer_from(sender, recipient, amount, data);
        }

        fn safe_transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
            data: Span<felt252>,
        ) {
            self.erc20.transfer_from(sender, recipient, amount);
            if !self._check_on_erc20_received(sender, recipient, amount, data) {
                self._throw_invalid_receiver(recipient);
            }
        }
    }

    #[generate_trait]
    impl SNIP88InternalImpl of SNIP88InternalTrait {
        fn _check_on_erc20_received(
            self: @ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
            data: Span<felt252>,
        ) -> bool {
            let src5_dispatcher = ISRC5Dispatcher { contract_address: recipient };
            if src5_dispatcher.supports_interface(ISNIP88_RECEIVER_ID) {
                ISNIP88ReceiverDispatcher { contract_address: recipient }
                    .on_erc20_received(
                        get_caller_address(), sender, amount, data
                    ) == ISNIP88_RECEIVER_ID
            } else {
                src5_dispatcher.supports_interface(ISRC6_ID)
            }
        }

        /// SNIP-64 error standard
        fn _throw_invalid_receiver(self: @ContractState, receiver: ContractAddress) {
            let data: Array<felt252> = array!['ERC20InvalidReceiver', receiver.into(),];
            panic(data);
        }
    }
}
