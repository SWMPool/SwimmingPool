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
    minted : Bool;
    inProgress : Bool;
  };
  public type DepositError = {
    #DepositInProgress;
    #WaitingForMint;
    #TransferFromError : T.TransferFromError;
    #Unknown; // TODO: better error
  };

  public type MintError = {
    #MintInProgress;
    #NoAvailableDeposit;
    #MintNotAvailable;
    #TransferFromError : T.TransferFromError;
    #Unknown; // TODO: better error
  };
  


  let despositStates: HashMap.HashMap<Principal, DepositState> = HashMap.HashMap<Principal, DepositState>(10, Principal.equal, Principal.hash);
  
  // Accept deposits
  // - user approves transfer: `token_a.icrc2_approve({ spender=borrow_canister; amount=amount; ... })`
  // - user deposits their token: `borrow_canister.deposit(amount)`
  // TODO: fee calculations?
  // TODO: returning error result vs trapping
  public shared ({ caller }) func deposit(amount : DepositAmount) : async Result.Result<DepositAmount, DepositError> {
    // Get the state of any existing deposit
    let existingState: ?DepositState = despositStates.get(caller);
    
    switch existingState {
      // Handle the case where a deposit is in progress.
      case (?state) {
        if (state.inProgress) {
          return #err(#DepositInProgress);
        };
        return #err(#WaitingForMint);
      };
      case null {
        // No deposit is in progress. We can start a new one.
        try {
          // Lock state.
          let newState = { amount = amount; minted = false; inProgress = true };
          despositStates.put(caller, newState);

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
            // Transfer succeeded. We can now mint the tokens.
            // TODO: is this the best return value? Maybe something more significant can be returned?
            case (#Ok(_)) { 
              let doneState = { newState with inProgress = false };
              despositStates.put(caller, doneState);

              #ok(amount)
            };
            // Transfer failed. Clean up lock.
            case (#Err(err)) {
              let _ = despositStates.delete(caller);
              return #err(#TransferFromError(err));
            };
          };
        } catch (err) {
          // Transfer trapped. Clean up lock.
          let _ = despositStates.delete(caller);
          return #err(#Unknown);
        };
      };
    };
  };

  // Accept deposits
  // - user deposits their token: `borrow_canister.deposit(amount)`
  // - user mints: `borrow_canister.mint()`
  // TODO: fee calculations?
  public shared ({ caller }) func mint() : async Result.Result<DepositAmount, MintError> {
    // Get the state of any existing deposit
    let existingState: ?DepositState = despositStates.get(caller);
    
    switch existingState {
      // Handle the case where a mint is in progress.
      case (?state) {
        if (state.inProgress) {
          return #err(#MintInProgress);
        };

        if (state.minted) {
          return #err(#MintNotAvailable);
        };

        try {
          // Lock state.
          let lockState = { state with inProgress = true};
          despositStates.put(caller, lockState);

          // Perform the transfer, to mint the tokens to the caller.
          let mintResult = await stable_token_actor.icrc1_transfer({
            to = { owner = caller; subaccount = null };
            amount = state.amount;
            from_subaccount = null;
            memo = null;
            fee = null;
            created_at_time = null;
          });

          // Check that the transfer was successful.
          let transfer = switch (mintResult) {
            // Transfer succeeded. Remove state.
            // TODO: is this the best return value? Maybe something more significant can be returned?
            case (#Ok(_)) { 
              let _ = despositStates.delete(caller);
              #ok(state.amount)
            };
            // Transfer failed. Release lock.
            case (#Err(err)) {
              despositStates.put(caller, { state with inProgress = false});
              return #err(#TransferFromError(err));
            };
          };
        } catch (err) {
          // Transfer trapped. Release lock.
          despositStates.put(caller, { state with inProgress = false});
          return #err(#Unknown);
        };
      };
      case null {
        return #err(#NoAvailableDeposit);
      };
    };
  };
};