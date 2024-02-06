import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Buffer "mo:base/Buffer";
import Result "mo:base/Result";
import Option "mo:base/Option";
import HashMap "mo:base/HashMap";
import Error "mo:base/Error";
import Debug "mo:base/Debug";

import LibUUID "mo:uuid/UUID";
import Source "mo:uuid/async/SourceV4";

import T "Types2";

shared ({ caller = _owner }) actor class Borrow(
  init_args : {
    collateral_token : Principal;
    stable_token : Principal;
  }
) = this {
  // token actors
  private let collateral_token_actor : T.TokenInterface = actor (Principal.toText(init_args.collateral_token));
  private let stable_token_actor : T.TokenInterface = actor (Principal.toText(init_args.stable_token));
  private let uuidGenerator = Source.Source();

  // types
  public type DepositAmount = Nat;
  public type UUID = Text;
  public type UUIDBuffer = Buffer.Buffer<UUID>;

  // state of deposit and withdraw operations
  public type LoanState = {
    depositTransfer: Bool;
    depositMint : Bool;
    withdrawTransfer : Bool;
    withdrawBurn : Bool;
    inProgress : Bool;
  };

  public type Loan = {
    uuid: UUID;
    principal: Principal;
    depositAmount : DepositAmount;
    state: LoanState;
  };


  public type LoanError = {
    #LoanNotFound;
  };

  public type DepositError = {
    #DepositInProgress;
    #ReachedUnknownState;
    #TransferFailed : { message : Text };
    #MintFailed : { message : Text };
    #TransferFromError : T.TransferFromError;
    #LoanError : LoanError;
  };


  // fast access to a loan by its UUID
  private let uuidToLoan: HashMap.HashMap<UUID, Loan> = HashMap.HashMap<UUID, Loan>(10, Text.equal, Text.hash);
  // array to maintain order of loans
  private let activeLoans: UUIDBuffer = Buffer.Buffer<UUID>(10);
  // fast access to loans by principal
  private let principalToLoans: HashMap.HashMap<Principal, UUIDBuffer> = HashMap.HashMap<Principal, UUIDBuffer>(10, Principal.equal, Principal.hash);

  // SHARED METHODS
  // Accept deposits
  // - user approves transfer: `token_a.icrc2_approve({ spender=borrow_canister; amount=amount; ... })`
  // - user deposits their token: `borrow_canister.deposit(amount)`
  public shared ({ caller }) func deposit(amount : DepositAmount) : async Result.Result<UUID, DepositError> {
    let loan = await newLoan(caller, amount);
    return await deposit_helper(loan.uuid);
  };

  // Retry deposit in case it fails at some point
  // TODO: is caller check needed? At this point the loan should be in the system with the correct principal.
  public func deposit_retry(loanUUID: UUID) : async Result.Result<UUID, DepositError> {
    return await deposit_helper(loanUUID);
  };

  // QUERY METHODS
  public query func getLoanByUUID(loanUUID: UUID) : async Result.Result<Loan, LoanError> {
    return getLoan(loanUUID);
  };

  public query func getLoansByPrincipal(principal: Principal) : async Result.Result<[Loan], LoanError> {
    switch (principalToLoans.get(principal)) {
      case (?uuids) {
        // mapFilter drops all null values
        let loansData: Buffer.Buffer<Loan> = Buffer.mapFilter<UUID, Loan>(uuids, func (uuid: UUID) {
          switch (getLoan(uuid)) {
            case (#ok(loan)) { ?loan };
            case (#err(err)) { null };
          };
        });
        
        return #ok(Buffer.toArray(loansData));
      };
      case (_) {
        return #ok([]);
      };
    };
  };


  // PRIVATE METHODS
  // internal method that handles deposit logic
  private func deposit_helper(loanUUID: UUID) : async Result.Result<UUID, DepositError> {
    switch (getLoan(loanUUID)) {
      case (#ok(loan)) {
        // Handle the case where a deposit is in progress.
        if (loan.state.inProgress == true) {
          return #err(#DepositInProgress);
        };

        // call transfer
        if (loan.state.depositTransfer == false and loan.state.depositMint == false) {
          // lock
          let _ = updateLoan({ loan with state = { loan.state with inProgress = true } });

          let transferResult = await transfer(loan.principal, loan.depositAmount);
          switch (transferResult) {
            case (#ok(_)) {
              // update state with successful transfer and release lock
              let _ =  updateLoan({ loan with state = { loan.state with transfer = true; inProgress = false} });
            };
            case (#err(err)) {
              // release lock
              let _ =  updateLoan({ loan with state = { loan.state with inProgress = false} });
              return #err(err);
            };
          };
        };

        // call mint
        if (loan.state.depositTransfer == true and loan.state.depositMint == false) {
          // lock
          let _ = updateLoan({ loan with state = { loan.state with inProgress = true } });

          let mintResult = await mint(loan.principal, loan.depositAmount);
          switch (mintResult) {
            case (#ok(_)) {
              // update state with successful mint and release lock
              let _ =  updateLoan({ loan with state = { loan.state with mint = true; inProgress = false} });
            };
            case (#err(err)) {
              // release lock
              let _ =  updateLoan({ loan with state = { loan.state with inProgress = false} });
              return #err(err);
            };
          };
        };

        // end state
        if (loan.state.depositTransfer == true and loan.state.depositMint == true) {
          // TODO: better value to be returned
          return #ok(loan.uuid);
        };

        return #err(#ReachedUnknownState);
      };
      case (#err(#LoanNotFound)) {
        return #err(#LoanError(#LoanNotFound));
      };
    };
  };

  // TODO: fee calculations?
  public func transfer(caller: Principal, amount : DepositAmount) : async Result.Result<DepositAmount, DepositError> {
    try {
      // Perform the transfer, to capture the tokens.
      let transferResult = await collateral_token_actor.icrc2_transfer_from({
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

  // LOAN HANDLERS
  private func newLoan(principal: Principal, depositAmount : DepositAmount) : async Loan {
    // TODO: how to use syncronius uuid generator?
    let loan = {
      uuid = LibUUID.toText(await uuidGenerator.new());
      principal;
      depositAmount;
      state = {
        depositTransfer = false;
        depositMint = false;
        withdrawTransfer = false;
        withdrawBurn = false;
        inProgress = false
      };
    };

    let _ = uuidToLoan.put(loan.uuid, loan);
    let _ = activeLoans.add(loan.uuid);
    let _ = Option.get(principalToLoans.get(loan.principal), Buffer.Buffer<UUID>(2)).add(loan.uuid);

    loan
  };

  private func deleteLoan(loanUUID: UUID) : Result.Result<Loan, LoanError> {
    let loan = uuidToLoan.get(loanUUID);
    switch (loan) {
      case (?loan) {
        activeLoans.filterEntries(func (_, uuid) { uuid == loanUUID });
        return #ok(loan);
      };
      case (_) {
        return #err(#LoanNotFound);
      };
    };
  };

  private func updateLoan(loan: Loan): Result.Result<UUID, LoanError> {
    let oldLoanData = uuidToLoan.replace(loan.uuid, loan);
    switch (oldLoanData) {
      case (?loan) {
        return #ok(loan.uuid);
      };
      case (_) {
        return #err(#LoanNotFound);
      };
    };
  };

  private func getLoan(loanUUID: UUID) : Result.Result<Loan, LoanError> {
    let loan = uuidToLoan.get(loanUUID);
    switch (loan) {
      case (?loan) {
        return #ok(loan);
      };
      case (_) {
        return #err(#LoanNotFound);
      };
    };
  };
};