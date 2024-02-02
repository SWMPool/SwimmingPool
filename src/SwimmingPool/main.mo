import Principal "mo:base/Principal";
import TrieMap "mo:base/TrieMap";
import Result "mo:base/Result";
import Option "mo:base/Option";
import HashMap "mo:base/HashMap";

import T "Types2";

import Debug "mo:base/Debug";
import Blob "mo:base/Blob";
import Error "mo:base/Error";

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

  public type WithdrawArgs = {
    amount : Nat;
    fee : ?Nat;
    memo : ?Blob;
    created_at_time : ?Nat64;
  };


  public type DepositAmount = Nat;
  public type DepositState = {
    amount : DepositAmount;
    transfer: Bool;
    mint : Bool;
    inProgress : Bool;
  };

  public type DepositError = {
    #DepositInProgress;
    #ReachedUnknownState;
    #TransferFailed : { message : Text };
    #MintFailed : { message : Text };
    #TransferFromError : T.TransferFromError;
  };

  let depositStates: HashMap.HashMap<Principal, DepositState> = HashMap.HashMap<Principal, DepositState>(10, Principal.equal, Principal.hash);

  // Accept deposits
  // - user approves transfer: `token_a.icrc2_approve({ spender=borrow_canister; amount=amount; ... })`
  // - user deposits their token: `borrow_canister.deposit(amount)`
  public shared ({ caller }) func deposit(amount: DepositAmount) : async Result.Result<DepositAmount, DepositError> {
    var state : DepositState = Option.get(
      depositStates.get(caller),
      { amount; transfer = false; mint = false; inProgress = false }
    );

    // Handle the case where a deposit is in progress.
    if (state.inProgress == true) {
      return #err(#DepositInProgress);
    };

    // call transfer
    if (state.transfer == false and state.mint == false) {
      // lock
      state := { state with inProgress = true };
      depositStates.put(caller, state);

      let transferResult = await transfer(caller, amount);
      switch (transferResult) {
        case (#ok(_)) {
          // update state with successful transfer and release lock
          state := { state with transfer = true; inProgress = false };
          depositStates.put(caller, state);
        };
        case (#err(err)) {
          // release lock
          state := { state with inProgress = false };
          depositStates.put(caller, state);

          return #err(err);
        };
      };
    };

    // call mint
    if (state.transfer == true and state.mint == false) {
      // lock
      state := { state with inProgress = true };
      depositStates.put(caller, state);

      let mintResult = await mint(caller, amount);
      switch (mintResult) {
        case (#ok(_)) {
          // update state with successful mint and release lock
          state := { state with mint = true; inProgress = false};
          depositStates.put(caller, state);
        };
        case (#err(err)) {
          // release lock
          state := { state with inProgress = false};
          depositStates.put(caller, state);

          return #err(err);
        };
      };
    };

    // end state
    if (state.transfer == true and state.mint == true) {
      // remove deposit state
      let _ = depositStates.delete(caller);

      // TODO: better value to be returned
      return #ok(amount);
    };

    return #err(#ReachedUnknownState);
  };

  // Get state of deposit
  public query func getDepositState(caller: Principal) : async ?DepositState {
    depositStates.get(caller)
  };

  // TODO: fee calculations?
  public func transfer(caller: Principal, amount : DepositAmount) : async Result.Result<DepositAmount, DepositError> {
    try {
      // Perform the transfer, to capture the tokens.
      let transferResult = await coll_token_actor.icrc2_transfer_from({
        amount;
        from = { owner = caller; subaccount = null };
        to = { owner = Principal.fromActor(this); subaccount = null };
        spender_subaccount = null;
        fee = null;
        memo = null;
        created_at_time = null;
      });

      // Check that the transfer was successful.
      let transfer = switch (transferResult) {
        // TODO: is this the best return value? Maybe something more significant can be returned?
        case (#Ok(_)) { #ok(amount) };
        case (#Err(err)) { return #err(#TransferFromError(err)); };
      };
    } catch (err) {
      return #err(#TransferFailed({ message = Error.message(err) }));
    };
  };

  // TODO: fee calculations?
  private func mint(caller: Principal, amount : DepositAmount) : async Result.Result<DepositAmount, DepositError> {
    try {
      // Perform the transfer, to mint the tokens to the caller.
      let mintResult = await stable_token_actor.icrc1_transfer({
        to = { owner = caller; subaccount = null };
        amount = amount;
        from_subaccount = null;
        memo = null;
        fee = null;
        created_at_time = null;
      });

      // Check that the transfer was successful.
      let transfer = switch (mintResult) {
        case (#Ok(_)) { #ok(amount) };
        case (#Err(err)) { return #err(#TransferFromError(err)); };
      };

    } catch (err) {
      return #err(#MintFailed({ message = Error.message(err) }));
    };
  };
};