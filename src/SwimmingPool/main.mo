import Principal "mo:base/Principal";
import TrieMap "mo:base/TrieMap";
import Result "mo:base/Result";
import Option "mo:base/Option";

import T "Types2";

import Debug "mo:base/Debug";

// track ownership of the borrow

shared ({ caller = _owner }) actor class Borrow(
  init_args : {
    coll_token : Principal;
    stable_token : Principal;
  }
) = this {
  let coll_token_actor : T.TokenInterface = actor (Principal.toText(init_args.coll_token));
  let stable_token_actor : T.TokenInterface = actor (Principal.toText(init_args.stable_token));

  // TODO: need to track the order in which the tokens are added
  // need a better structure than map
  private var coll_balances = TrieMap.TrieMap<Principal, Nat>(Principal.equal, Principal.hash);

  public type DepositArgs = {
    amount : Nat;
    fee : ?Nat;
    memo : ?Blob;
    created_at_time : ?Nat64;
  };

  public type WithdrawArgs = {
    amount : Nat;
    fee : ?Nat;
    memo : ?Blob;
    created_at_time : ?Nat64;
  };

  public type DepositError = {
    #TransferFromError : T.TransferFromError;
  };

  // Accept deposits
  // - user approves transfer: `token_a.icrc2_approve({ spender=borrow_canister; amount=amount; ... })`
  // - user deposits their token: `borrow_canister.deposit({ token=token_a; amount=amount; ... })`
  // - These deposit handlers show how to safely accept and register deposits of an ICRC-2 token.
  public shared ({ caller }) func deposit(args : DepositArgs) : async Result.Result<Nat, DepositError> {

    // TODO: check if we need to calculate fee
    // let fee = switch (args.fee) {
    //   case (?f) { f };
    //   case (null) { await token.icrc1_fee() };
    // };

    // Perform the transfer, to capture the tokens.
    let transfer_result = await coll_token_actor.icrc2_transfer_from({
      spender_subaccount = null;
      from = { owner = caller; subaccount = null };
      to = { owner = Principal.fromActor(this); subaccount = null };
      amount = args.amount;
      fee = args.fee;
      memo = args.memo;
      created_at_time = args.created_at_time;
    });


    // Check that the transfer was successful.
    let transfer_block_height = switch (transfer_result) {
      case (#Ok(block_height)) { block_height };
      case (#Err(err)) {
        // Transfer failed. There's no cleanup for us to do since no state has
        // changed, so we can just wrap and return the error to the frontend.
        return #err(#TransferFromError(err));
      };
    };



    // Update the balance of the sender.
    // TODO: check if the rest of the code fails do we need to revert the transfer manually?
    let old_balance = Option.get(coll_balances.get(caller), 0 : Nat);
    coll_balances.put(caller, old_balance + args.amount);


    let mint_result = await stable_token_actor.icrc1_transfer({
      to = { owner = caller; subaccount = null };
      amount = args.amount;
      from_subaccount = null;
      memo = null;
      fee = null;
      created_at_time = null;
    });


    // Check that the mint was successful.
    let mint_block_height = switch (mint_result) {
      case (#Ok(block_height)) { block_height };
      case (#Err(err)) {
        // Transfer failed. There's no cleanup for us to do since no state has
        // changed, so we can just wrap and return the error to the frontend.
        return #err(#TransferFromError(err));
      };
    };

    // Return the "block height" of the transfer
    #ok(mint_block_height)
  };

  // Accept withdraw
  // - user approves transfer: `token_b.icrc2_approve({ spender=borrow_canister; amount=amount; ... })`
  // - user deposits their token: `borrow_canister.withdraw({ token=token_b; amount=amount; ... })`
  // - These deposit handlers show how to safely accept and register deposits of an ICRC-2 token.
  public shared ({ caller }) func withdraw(args : DepositArgs) : async Result.Result<Nat, DepositError> {
    // TODO: check if the caller has enough balance

    // TODO: check if we need to calculate fee
    // let fee = switch (args.fee) {
    //   case (?f) { f };
    //   case (null) { await token.icrc1_fee() };
    // };

    // Perform the transfer, to capture the tokens.
    let burn_result = await stable_token_actor.icrc2_transfer_from({
      spender_subaccount = null;
      from = { owner = caller; subaccount = null };
      to = { owner = Principal.fromActor(this); subaccount = null };
      amount = args.amount;
      fee = args.fee;
      memo = args.memo;
      created_at_time = args.created_at_time;
    });

    // Check that the transfer was successful.
    let burnr_block_height = switch (burn_result) {
      case (#Ok(block_height)) { block_height };
      case (#Err(err)) {
        // Transfer failed. There's no cleanup for us to do since no state has
        // changed, so we can just wrap and return the error to the frontend.
        return #err(#TransferFromError(err));
      };
    };

    // Update the balance of the sender.
    // TODO: check if the rest of the code fails do we need to revert the transfer manually?
    let old_balance = Option.get(coll_balances.get(caller), 0 : Nat);
    coll_balances.put(caller, old_balance - args.amount);

    let transfer_result = await coll_token_actor.icrc1_transfer({
      to = { owner = caller; subaccount = null };
      amount = args.amount;
      from_subaccount = null;
      memo = null;
      fee = null;
      created_at_time = null;
    });

    // Check that the mint was successful.
    let transfer_block_height = switch (transfer_result) {
      case (#Ok(block_height)) { block_height };
      case (#Err(err)) {
        // Transfer failed. There's no cleanup for us to do since no state has
        // changed, so we can just wrap and return the error to the frontend.
        return #err(#TransferFromError(err));
      };
    };

    // Return the "block height" of the transfer
    #ok(transfer_block_height)
  };

};
