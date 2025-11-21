public without sharing class IC_RollUpPayeeInterest {
  public class PayeeAssociation {
    public Id caseIssueId;
    public Decimal factor;
  }

  Id caseId;
  List<Payee__c> payees;

  public IC_RollUpPayeeInterest(Id caseId) {
    this.caseId = caseId;
  }

  public void calculateInterest() {
    payees = [
      SELECT
        Id,
        NetWages__c,
        Factor__c,
        Post_Citation_Interest_for_Wages_for_EE1__c,
        Post_Judgment_Interest_For_Wages_for_EE1__c,
        Payee_Association_JSON__c
      FROM Payee__c
      WHERE Case_Management__c = :caseId
      ORDER BY NetWages__c DESC NULLS LAST
    ];

    if (payees.isEmpty())
      return;

    Set<Id> usedCaseIssueIds = new Set<Id>();
    Map<Id, List<PayeeAssociation>> payeeToAssociations = new Map<Id, List<PayeeAssociation>>();
    Boolean hasJsonData = false;

    // STEP 1: Parse JSON and collect ONLY used Case Issues
    for (Payee__c p : payees) {
      if (String.isNotBlank(p.Payee_Association_JSON__c)) {
        try {
          List<PayeeAssociation> associations = (List<PayeeAssociation>) JSON.deserialize(
            p.Payee_Association_JSON__c,
            List<PayeeAssociation>.class
          );
          List<PayeeAssociation> valid = new List<PayeeAssociation>();
          for (PayeeAssociation assoc : associations) {
            if (assoc.caseIssueId != null && assoc.factor != null) {
              usedCaseIssueIds.add(assoc.caseIssueId);
              valid.add(assoc);
              hasJsonData = true;
            }
          }
          if (!valid.isEmpty()) {
            payeeToAssociations.put(p.Id, valid);
          }
        } catch (Exception e) {
          System.debug('JSON Error: ' + e.getMessage());
        }
      }
    }

    // STEP 2: Query ONLY the Case Issues that are actually used
    Map<Id, DIR_Violation__c> vioMap = new Map<Id, DIR_Violation__c>();
    if (!usedCaseIssueIds.isEmpty()) {
      vioMap = new Map<Id, DIR_Violation__c>(
        [
          SELECT
            Id,
            Post_Citation_Interest_for_Wages__c,
            Post_Judgment_Interest_for_Wages__c
          FROM DIR_Violation__c
          WHERE Id IN :usedCaseIssueIds
        ]
      );
    } else {
      // Legacy case — query ALL violations for this Case
      vioMap = new Map<Id, DIR_Violation__c>(
        [
          SELECT
            Id,
            Post_Citation_Interest_for_Wages__c,
            Post_Judgment_Interest_for_Wages__c
          FROM DIR_Violation__c
          WHERE Case__c = :caseId
        ]
      );
    }

    if (vioMap.isEmpty())
      return;

    // STEP 3: Calculate raw interest per Payee
    Map<Id, Decimal> payeeRawCit = new Map<Id, Decimal>();
    Map<Id, Decimal> payeeRawJud = new Map<Id, Decimal>();

    for (Payee__c p : payees) {
      Decimal cit = 0;
      Decimal jud = 0;

      if (hasJsonData && payeeToAssociations.containsKey(p.Id)) {
        // NEW: Use JSON
        for (PayeeAssociation assoc : payeeToAssociations.get(p.Id)) {
          DIR_Violation__c v = vioMap.get(assoc.caseIssueId);
          if (v != null) {
            Decimal share = assoc.factor / 100;
            cit += (v.Post_Citation_Interest_for_Wages__c ?? 0) * share;
            jud += (v.Post_Judgment_Interest_for_Wages__c ?? 0) * share;
          }
        }
      } else {
        // LEGACY: Use Factor__c on ALL violations
        Decimal factor = (p.Factor__c != null) ? p.Factor__c / 100 : 0;
        for (DIR_Violation__c v : vioMap.values()) {
          cit += (v.Post_Citation_Interest_for_Wages__c ?? 0) * factor;
          jud += (v.Post_Judgment_Interest_for_Wages__c ?? 0) * factor;
        }
      }

      payeeRawCit.put(p.Id, cit);
      payeeRawJud.put(p.Id, jud);
    }

    // STEP 4: Expected totals = sum of ONLY used Case Issues
    Decimal expectedCit = 0, expectedJud = 0;
    for (DIR_Violation__c v : vioMap.values()) {
      expectedCit += (v.Post_Citation_Interest_for_Wages__c ?? 0);
      expectedJud += (v.Post_Judgment_Interest_for_Wages__c ?? 0);
    }

    // STEP 5: Apply rounded values
    for (Payee__c p : payees) {
      p.Post_Citation_Interest_for_Wages_for_EE1__c = (payeeRawCit.get(p.Id) ??
          0)
        .setScale(2, RoundingMode.HALF_UP);
      p.Post_Judgment_Interest_For_Wages_for_EE1__c = (payeeRawJud.get(p.Id) ??
          0)
        .setScale(2, RoundingMode.HALF_UP);
    }

    // STEP 6: Balance — total matches expected
    balanceGlobally(
      payees,
      'Post_Citation_Interest_for_Wages_for_EE1__c',
      expectedCit
    );
    balanceGlobally(
      payees,
      'Post_Judgment_Interest_For_Wages_for_EE1__c',
      expectedJud
    );

    // STEP 7: Update
    Database.update(payees, false);
  }
  /*
    private static void balanceGlobally(List<Payee__c> payees, String field, Decimal target) {
        if (target == 0) return;
        Decimal total = 0;
        for (Payee__c p : payees) total += (Decimal) p.get(field);
        Decimal diff = target - total.setScale(2, RoundingMode.HALF_UP);
        if (diff == 0) return;

        Integer i = 0;
        while (Math.abs(diff) >= 0.01 && i < payees.size()) {
            Payee__c p = payees[i];
            Decimal val = (Decimal) p.get(field);
            p.put(field, diff > 0 ? val + 0.01 : val - 0.01);
            diff += diff > 0 ? -0.01 : 0.01;
            i++;
        }
    }
   */
  private static void balanceGlobally(
    List<Payee__c> payees,
    String field,
    Decimal target
  ) {
    if (target == 0 || payees.isEmpty())
      return;

    // Step 1: Current total after rounding
    Decimal currentTotal = 0;
    for (Payee__c p : payees) {
      currentTotal += (Decimal) p.get(field);
    }

    Decimal roundedCurrent = currentTotal.setScale(2, RoundingMode.HALF_UP);
    Decimal diff = target - roundedCurrent;
    if (diff == 0)
      return;

    // Step 2: Convert diff to pennies — 100% safe, no multiply()
    Integer penniesToAdjust = (Integer) Math.round(diff * 100);

    if (penniesToAdjust == 0)
      return;

    Integer i = 0;
    while (penniesToAdjust != 0 && i < payees.size()) {
      Payee__c p = payees[i];
      Decimal val = (Decimal) p.get(field);

      if (penniesToAdjust > 0) {
        p.put(field, val + 0.01);
        penniesToAdjust--;
      } else {
        p.put(field, val - 0.01);
        penniesToAdjust++;
      }
      i++;
    }

    // Final force-adjust (should never happen)
    if (penniesToAdjust != 0 && !payees.isEmpty()) {
      Payee__c last = payees[payees.size() - 1];
      Decimal lastVal = (Decimal) last.get(field);
      last.put(field, lastVal + (penniesToAdjust * 0.01));
    }
  }
}