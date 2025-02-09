DECLARE @LOBID NVARCHAR(50) = '745461,10990326',
        @DocumentStatus NVARCHAR(50) = '1,21,244,22,23,24,142,169,210,25,41,42,150';

-- Temporary table to store status IDs
DECLARE @Status TABLE (StatusId BIGINT);


-- Temporary table to store LOB IDs
DECLARE @LOBIDs TABLE (entityDetailCode BIGINT);

-- Insert values from the comma-separated DocumentStatus into the temporary table
INSERT INTO @Status
(
    StatusId
)
SELECT CAST(Value AS BIGINT)
FROM STRING_SPLIT(@DocumentStatus, ',');

-- Insert values from the comma-separated LOBIds into the temporary table
INSERT INTO @LOBIDs
(
    entityDetailCode
)
SELECT CAST(Value AS BIGINT)
FROM STRING_SPLIT(@LOBID, ',');



DROP TABLE IF EXISTS #OrderIds;

-- Select distinct Document Codes and Business Unit (BU) Codes into #OrderIds table
SELECT DISTINCT
    CASE
        WHEN ord.OrderSource = 5
             AND doc.DocumentStatus IN ( 1, 21, 22, 23, 24 ) THEN
            ParentDocumentCode
        ELSE
            Ord.OrderId
    END AS DocumentCode,
    EntityDetails.EntityCode AS BU
INTO #OrderIds
FROM Dm_Documents AS doc WITH (NOLOCK)
    INNER JOIN @Status AS docstatus
        ON doc.DocumentStatus = docstatus.StatusId
    INNER JOIN P2P_Orders AS Ord WITH (NOLOCK)
        ON ORD.OrderID = doc.DocumentCode
    INNER JOIN DM_DocumentBU AS BU WITH (NOLOCK)
        ON BU.DocumentCode = doc.DocumentCode
    INNER JOIN ORG_EntityDetails AS EntityDetails WITH (NOLOCK)
        ON EntityDetails.EntityDetailCode = BU.BUCode
    INNER JOIN PRN_PartnerDetails AS PRND WITH (NOLOCK)
        ON PRND.PartnerCode = Ord.PartnerCode
WHERE doc.IsDeleted = 0
      AND EntityDetails.LOBEntityDetailCode in (select entityDetailCode from @LOBIDs)
      AND EntityDetails.EntityId IN ( 9, 44 )
      AND EntityDetails.EntityDetailCode IN ( 745471, 853462, 1218826, 2338289,1084116,11096063,11096059,11096060,11096061,11096064,11096065 )
      AND doc.IsBuyerVisible = 1
      AND (
              ord.IsCloseForInvoicing = 0
              OR ord.IsCloseForReceiving = 0
          )
      AND ord.ClosingOrderStatus != 124
      AND PRND.PartnerStatusCode NOT IN ( 3, 7 ) and doc.DocumentNumber in  ('0060008732-002','0060565230-001','0060605574')
	  ;

----------------------------------- Credit Memo Details Started -----------------------------------
DROP TABLE IF EXISTS #parentorderItems

SELECT poItems.OrderID,
       OrderItemId,
       P2PLineItemID,
       Quantity,
       Unitprice,
       poItems.ReceivingStatus,
       lineAsnStatus,
       poItems.Tax,
       ShippingCharges,
       poItems.AdditionalCharges,
       DateNeeded,
       DateRequested,
       StartDate,
       EndDate,
       DiscountPercentage,
       MarkUpPercentage,
       Discount,
       MarkUp,
       poItems.IsDeleted,
       poItems.ItemExtendedType,
       poItems.Quantity as [ParentQtyCOCR],
       poItems.ExternalTax,
       poItems.ContractNo
INTO #parentorderItems
FROM dbo.P2P_OrderItems AS poItems WITH (NOLOCK)
    INNER JOIN P2P_Orders AS ORD
        ON poItems.OrderId = ORD.ParentDocumentCode
    INNER JOIN #OrderIds AS OI
        ON ORD.OrderID = OI.DocumentCode
WHERE poItems.IsDeleted = 0

DROP TABLE IF EXISTS #tmpOrderInvoiceMaping
CREATE TABLE #tmpOrderInvoiceMaping
(
    InvoiceId BIGINT,
    OrderId BIGINT
)

INSERT INTO #tmpOrderInvoiceMaping
SELECT InvoiceId,
       OrderId
FROM P2P_OrderInvoiceMapping AS OIM WITH (NOLOCK)
    INNER JOIN #OrderIds AS OI
        ON OIM.OrderId = OI.DocumentCode

--SELECT * FROM #tmpOrderInvoiceMaping

DROP TABLE IF EXISTS #tmpInvoiceItems
CREATE TABLE #tmpInvoiceItems
(
    InvoiceItemID BIGINT,
    P2PLineItemID BIGINT,
    InvoiceId BIGINT,
    IsDeleted INT,
    Quantity DECIMAL(18, 6),
    ItemExtendedType INT,
    InvoiceStatus INT,
    CreditType TINYINT,
    UnitPrice DECIMAL(18, 6),
    Tax DECIMAL(18, 6),
    AdditionalCharges DECIMAL(18, 6),
    ShippingCharges DECIMAL(18, 6)
)

INSERT INTO #tmpInvoiceItems
SELECT InvoiceItemID,
       P2PLineItemID,
       P2P_InvoiceItems.InvoiceId,
       P2P_InvoiceItems.IsDeleted,
       Quantity,
       ItemExtendedType,
       DM_Documents.DocumentStatus,
       CreditType,
       UnitPrice,
       Tax,
       AdditionalCharges,
       ShippingCharges
FROM P2P_InvoiceItems
    INNER JOIN #tmpOrderInvoiceMaping
        ON P2P_InvoiceItems.InvoiceId = #tmpOrderInvoiceMaping.InvoiceId
    INNER JOIN DM_Documents WITH (NOLOCK)
        ON #tmpOrderInvoiceMaping.InvoiceId = DM_Documents.DocumentCode
    INNER JOIN #OrderIds AS OI
        ON #tmpOrderInvoiceMaping.orderid = OI.DocumentCode
WHERE P2P_InvoiceItems.IsDeleted = 0
      AND DocumentStatus IN ( 68, 77, 102, 104, 105, 153 )

DROP TABLE IF EXISTS #tmpCreditDetails
CREATE TABLE #tmpCreditDetails
(
    CREDITMEMOCOUNT INT,
    CREDITQTY DECIMAL(18, 6),
    CREDITAMOUNT DECIMAL(18, 6),
    OrderItemId BIGINT
)

CREATE CLUSTERED INDEX tempCreditDetailsIndex
ON #tmpCreditDetails (OrderItemId)

INSERT INTO #tmpCreditDetails
Select Count(DISTINCT (CreditMemoId)),
       SUM(ISNULL(CreditQuantity, 0)),
       (SUM(ISNULL(CreditAmount, 0)) + SUM(ISNULL(P2P_CreditMemoItems.Tax, 0))
        + SUM(ISNULL(P2P_CreditMemoItems.ShippingCharges, 0)) + SUM(ISNULL(P2P_CreditMemoItems.AdditionalCharges, 0))
       ) as CreditAmount,
       poItems.OrderItemId
FROM P2P_OrderItems poItems WITH (NOLOCK)
    INNER JOIN #tmpOrderInvoiceMaping
        ON poItems.OrderId = #tmpOrderInvoiceMaping.OrderId
    INNER JOIN #tmpInvoiceItems
        ON #tmpInvoiceItems.InvoiceId = #tmpOrderInvoiceMaping.InvoiceId
           AND poItems.P2PLineItemID = #tmpInvoiceItems.P2PLineItemID
    INNER JOIN P2P_CreditMemoItems
        ON P2P_CreditMemoItems.InvoiceItemId = #tmpInvoiceItems.InvoiceItemId
           AND #tmpInvoiceItems.IsDeleted = 0
    INNER JOIN DM_documents WITH (NOLOCK)
        ON P2P_CreditMemoItems.CreditMemoId = DM_documents.DocumentCode
           and DM_documents.IsDeleted = 0
    INNER JOIN #OrderIds AS OI
        ON poItems.OrderId = OI.DocumentCode
WHERE P2P_CreditMemoItems.IsDeleted = 0
      AND poItems.IsDeleted = 0
      AND #tmpInvoiceItems.IsDeleted = 0
      AND DM_documents.DocumentStatus IN ( 101, 102, 156 )
GROUP BY poItems.OrderItemId
INSERT INTO #tmpCreditDetails
SELECT Count(CreditMemoId),
       SUM(ISNULL(CreditQuantity, 0)),
       (SUM(ISNULL(CreditAmount, 0)) + SUM(ISNULL(P2P_CreditMemoItems.Tax, 0))
        + SUM(ISNULL(P2P_CreditMemoItems.ShippingCharges, 0)) + SUM(ISNULL(P2P_CreditMemoItems.AdditionalCharges, 0))
       ) as CreditAmount,
       poItems.OrderItemId
FROM P2P_OrderItems poItems WITH (NOLOCK)
    INNER JOIN P2P_CreditMemoItems
        on P2P_CreditMemoItems.OrderItemId = poItems.OrderItemID
           AND poItems.IsDeleted = 0
           AND (
                   P2P_CreditMemoItems.InvoiceItemId is null
                   or P2P_CreditMemoItems.InvoiceItemId = 0
               )
    INNER JOIN DM_documents WITH (NOLOCK)
        on P2P_CreditMemoItems.CreditMemoId = DM_documents.DocumentCode
           and DM_documents.IsDeleted = 0
    INNER JOIN #OrderIds AS OI
        ON poItems.OrderId = OI.DocumentCode
WHERE P2P_CreditMemoItems.IsDeleted = 0
      AND poItems.IsDeleted = 0
      AND DM_documents.DocumentStatus IN ( 101, 102, 156 )
GROUP BY poItems.OrderItemId
INSERT INTO #tmpCreditDetails
Select Count(CreditMemoId),
       SUM(ISNULL(CreditQuantity, 0)),
       (SUM(ISNULL(CreditAmount, 0)) + SUM(ISNULL(P2P_CreditMemoItems.Tax, 0))
        + SUM(ISNULL(P2P_CreditMemoItems.ShippingCharges, 0)) + SUM(ISNULL(P2P_CreditMemoItems.AdditionalCharges, 0))
       ) as CreditAmount,
       #parentOrderItems.OrderItemId
FROM #parentOrderItems
    INNER JOIN #tmpOrderInvoiceMaping
        ON #parentOrderItems.OrderId = #tmpOrderInvoiceMaping.OrderId
    INNER JOIN #tmpInvoiceItems
        ON #tmpInvoiceItems.InvoiceId = #tmpOrderInvoiceMaping.InvoiceId
           AND #parentOrderItems.P2PLineItemID = #tmpInvoiceItems.P2PLineItemID
    INNER JOIN P2P_CreditMemoItems
        ON P2P_CreditMemoItems.InvoiceItemId = #tmpInvoiceItems.InvoiceItemId
           AND #tmpInvoiceItems.IsDeleted = 0
    INNER JOIN DM_documents WITH (NOLOCK)
        ON P2P_CreditMemoItems.CreditMemoId = DM_documents.DocumentCode
           and DM_documents.IsDeleted = 0
    INNER JOIN #OrderIds AS OI
        ON #parentOrderItems.OrderId = OI.DocumentCode
WHERE P2P_CreditMemoItems.IsDeleted = 0
      AND #parentOrderItems.IsDeleted = 0
      AND #tmpInvoiceItems.IsDeleted = 0
      AND DM_documents.DocumentStatus IN ( 101, 102, 156 )
GROUP BY #parentOrderItems.OrderItemId
INSERT INTO #tmpCreditDetails
SELECT Count(CreditMemoId),
       SUM(ISNULL(CreditQuantity, 0)),
       (SUM(ISNULL(CreditAmount, 0)) + SUM(ISNULL(P2P_CreditMemoItems.Tax, 0))
        + SUM(ISNULL(P2P_CreditMemoItems.ShippingCharges, 0)) + SUM(ISNULL(P2P_CreditMemoItems.AdditionalCharges, 0))
       ) as CreditAmount,
       #parentOrderItems.OrderItemId
FROM #parentOrderItems
    INNER JOIN P2P_CreditMemoItems
        on P2P_CreditMemoItems.OrderItemId = #parentOrderItems.OrderItemID
           AND #parentOrderItems.IsDeleted = 0
           AND (
                   P2P_CreditMemoItems.InvoiceItemId is null
                   or P2P_CreditMemoItems.InvoiceItemId = 0
               )
    INNER JOIN DM_documents WITH (NOLOCK)
        on P2P_CreditMemoItems.CreditMemoId = DM_documents.DocumentCode
           and DM_documents.IsDeleted = 0
    INNER JOIN #OrderIds AS OI
        ON #parentOrderItems.OrderId = OI.DocumentCode
WHERE P2P_CreditMemoItems.IsDeleted = 0
      AND #parentOrderItems.IsDeleted = 0
      AND DM_documents.DocumentStatus IN ( 101, 102, 156 )
GROUP BY #parentOrderItems.OrderItemId

DROP TABLE IF EXISTS #tmpCreditMemoDetails
CREATE TABLE #tmpCreditMemoDetails
(
    P2PLineItemID BIGINT,
    CreditMemoCount INT,
    CreditMemoQuantity DECIMAL(18, 6),
    CreditMemoAmount DECIMAL(18, 6),
    OrderItemId BIGINT
)

INSERT INTO #tmpCreditMemoDetails
SELECT poItems.P2PLineItemID as P2PLineItemID,
       CREDITMEMOCOUNT as CreditMemoCount,
       CASE
           WHEN poItems.ItemExtendedType = 2 THEN
               1
           ELSE
               CREDITQTY
       END AS CreditMemoQuantity,
       ISNULL(CREDITAMOUNT, 0) AS CreditMemoAmount,
       #tmpCreditDetails.OrderItemId
from #tmpCreditDetails
    INNER JOIN P2P_OrderItems poItems
        ON #tmpCreditDetails.OrderItemId = poItems.OrderItemID
    INNER JOIN #OrderIds AS OI
        ON poItems.OrderId = OI.DocumentCode

INSERT INTO #tmpCreditMemoDetails
SELECT #parentOrderItems.P2PLineItemID as P2PLineItemID,
       CREDITMEMOCOUNT as CreditMemoCount,
       CASE
           WHEN #parentOrderItems.ItemExtendedType = 2 THEN
               1
           ELSE
               CREDITQTY
       END AS CreditMemoQuantity,
       ISNULL(CREDITAMOUNT, 0) AS CreditMemoAmount,
       #tmpCreditDetails.OrderItemId
from #tmpCreditDetails
    INNER JOIN #parentOrderItems
        ON #tmpCreditDetails.OrderItemId = #parentOrderItems.OrderItemID
ORDER BY #parentOrderItems.OrderItemId

DROP TABLE IF EXISTS #OrderCreditMemoDetails
CREATE TABLE #OrderCreditMemoDetails
(
    P2PLineItemId BIGINT,
    CreditQty DECIMAL(18, 6),
    CreditAmount DECIMAL(18, 6),
    CreditCount INT
)

INSERT INTO #OrderCreditMemoDetails
(
    P2PLineItemID,
    CreditCount,
    CreditQty,
    CreditAmount
)
SELECT P2PLineItemID,
       sum(isnull(CreditMemoCount, 0)) AS CreditCount,
       sum(isnull(CreditMemoQuantity, 0)) AS CreditQty,
       sum(isnull(CreditMemoAmount, 0)) AS CreditAmount
from #tmpCreditMemoDetails
GROUP BY P2PLineItemID,
         OrderItemId
ORDER BY OrderItemId

--SELECT * FROM #OrderCreditMemoDetails

DROP TABLE IF EXISTS #tmpCreditInvoiceDetails
CREATE TABLE #tmpCreditInvoiceDetails
(
    CreditCount INT,
    CreditQty DECIMAL(18, 6),
    CreditAmount DECIMAL(18, 6),
    P2PLineItemId BIGINT
)

INSERT INTO #tmpCreditInvoiceDetails
SELECT Count(DISTINCT (tmpitems.InvoiceId)),
       SUM(   CASE
                  WHEN tmpitems.CreditType = 1 THEN
                      ISNULL(tmpitems.Quantity, 0)
                  ELSE
                      0
              END
          ),
       (SUM(ISNULL(tmpitems.UnitPrice, 0) * ISNULL(tmpitems.Quantity, 0)) + SUM(ISNULL(tmpitems.Tax, 0))
        + SUM(ISNULL(tmpitems.ShippingCharges, 0)) + SUM(ISNULL(tmpitems.AdditionalCharges, 0))
       ) as CreditAmount,
       tmpitems.P2PLineItemID
FROM #tmpInvoiceItems tmpitems
    INNER JOIN P2P_Invoices inv
        on inv.InvoiceId = tmpitems.InvoiceId
           AND (
                   inv.InvoiceType = 6
                   OR tmpitems.InvoiceStatus = 153
               )
GROUP BY tmpitems.P2PLineItemID

--SELECT * FROM #tmpCreditInvoiceDetails
DROP TABLE IF EXISTS #CreditMemoItems;

SELECT ri.OrderItemId,
       ISNULL(ordCrdMemo.CreditQty, 0) + ISNULL(crdInvoice.CreditQty, 0) AS CreditQuantity,
       ISNULL(ordCrdMemo.CreditAmount, 0) + ISNULL(crdInvoice.CreditAmount, 0) AS CreditAmount,
       ISNULL(ordCrdMemo.CreditCount, 0) + ISNULL(crdInvoice.CreditCount, 0) AS CreditMemoCount
INTO #CreditMemoItems
FROM P2P_OrderItems AS ri
    INNER JOIN #OrderIds AS OI
        ON ri.OrderId = OI.DocumentCode
    LEFT JOIN #OrderCreditMemoDetails ordCrdMemo
        ON ordCrdMemo.P2PLineItemID = ri.P2PLineItemID
    LEFT JOIN #tmpCreditInvoiceDetails crdInvoice
        ON crdInvoice.P2PLineItemId = ri.P2PLineItemID
----------------------------------- Credit Memo Details Ended -----------------------------------

-------------------------------- Order Material Lines Details Started -----------------------------------

-- Drop and create temporary table for material line purchase orders
DROP TABLE IF EXISTS #TempMaterialLinePOs_All;
CREATE TABLE #TempMaterialLinePOs_All
(
    OrderID BIGINT,
    LineNumber INT,
    OrderItemId BIGINT,
    P2PLineItemId BIGINT,
    Quantity DECIMAL(18, 6),
    UnitPrice DECIMAL(18, 6),
    DifferenceQuantity DECIMAL(36, 18)
        DEFAULT 0,
    TotalAcceptedAmount DECIMAL(36, 18)
        DEFAULT 0
);

-- Insert distinct values into #TempMaterialLinePOs_All
INSERT INTO #TempMaterialLinePOs_All
(
    OrderID,
    LineNumber,
    OrderItemId,
    P2PLineItemId,
    Quantity,
    UnitPrice
)
SELECT DISTINCT
    POI.OrderId,
    POI.LineNumber,
    POI.OrderItemId,
    POI.P2PLineItemID,
    POI.Quantity,
    POI.UnitPrice
FROM #OrderIds AS Ids WITH (NOLOCK)
    INNER JOIN DM_Documents AS D WITH (NOLOCK)
        ON Ids.DocumentCode = D.DocumentCode
    INNER JOIN P2P_OrderItems AS POI WITH (NOLOCK)
        ON POI.OrderId = Ids.DocumentCode
    INNER JOIN P2P_Orders AS P WITH (NOLOCK)
        ON D.DocumentCode = P.OrderId
WHERE POI.ItemExtendedType = 1
      AND POI.ClosingOrderStatus <> 124
      AND POI.IsDeleted = 0
      AND POI.ItemStatus <> 121
      AND D.IsDeleted = 0;

-- Drop and create temporary table for line total value of material purchase orders
DROP TABLE IF EXISTS #LineTotalValueOfMaterialPOs_ALL;
CREATE TABLE #LineTotalValueOfMaterialPOs_ALL
(
    Orderid BIGINT,
    LineNumber INT,
    Quantity DECIMAL(18, 6),
    UnitPrice DECIMAL(18, 6),
    CurrentOrderLineTotal DECIMAL(18, 6),
    P2PLineItemId BIGINT
);

-- Insert distinct values into #LineTotalValueOfMaterialPOs_ALL
INSERT INTO #LineTotalValueOfMaterialPOs_ALL
(
    OrderId,
    LineNumber,
    Quantity,
    UnitPrice,
    CurrentOrderLineTotal,
    P2PLineItemId
)
SELECT DISTINCT
    TML.Orderid,
    TML.LineNumber,
    TML.Quantity,
    TML.UnitPrice,
    TML.UnitPrice * TML.Quantity AS CurrentOrderLineTotal,
    TML.P2PLineItemId
FROM #TempMaterialLinePOs_All AS TML WITH (NOLOCK);

-- Drop and create temporary table for receipt lines
DROP TABLE IF EXISTS #ReceiptLines_All;
CREATE TABLE #ReceiptLines_All
(
    OrderId BIGINT,
    P2PLineItemId BIGINT,
    TotalAcceptedQuantity DECIMAL(18, 6)
);

-- Insert distinct values into #ReceiptLines_All
INSERT INTO #ReceiptLines_All
(
    OrderId,
    P2PLineItemId,
    TotalAcceptedQuantity
)
SELECT DISTINCT
    LTP.OrderId,
    LTP.P2PLineItemId,
    SUM(PRI.AcceptedQuantity) AS TotalAcceptedQuantity
FROM P2P_ReceiptItems AS PRI WITH (NOLOCK)
    INNER JOIN #LineTotalValueOfMaterialPOs_ALL AS LTP WITH (NOLOCK)
        ON PRI.P2PLineItemId = LTP.P2PLineItemId
    INNER JOIN P2P_Receipts AS PR WITH (NOLOCK)
        ON PRI.ReceiptId = PR.ReceiptId
    INNER JOIN DM_Documents AS D WITH (NOLOCK)
        ON PR.ReceiptId = D.DocumentCode
    INNER JOIN P2P_OrderReceiptMapping AS ORM WITH (NOLOCK)
        ON ORM.ReceiptId = D.DocumentCode
           AND LTP.OrderId = ORM.OrderId
WHERE ISNULL(D.DocumentStatus, 0) = 175
      AND PRI.ItemStatus <> 121
      AND D.IsDeleted = 0
      AND PRI.IsDeleted = 0
      AND PR.IsDeleted = 0
GROUP BY LTP.P2PLineItemId,
         LTP.OrderId;

-- Drop and create temporary table for material line purchase orders
DROP TABLE IF EXISTS #TempMaterialLinePOs;
CREATE TABLE #TempMaterialLinePOs
(
    OrderID BIGINT,
    LineNumber INT,
    OrderItemId BIGINT,
    P2PLineItemId BIGINT,
    Quantity DECIMAL(18, 6),
    UnitPrice DECIMAL(18, 6),
    DifferenceQuantity DECIMAL(36, 18)
        DEFAULT 0,
    TotalAcceptedAmount DECIMAL(36, 18)
        DEFAULT 0
);

-- Insert distinct values into #TempMaterialLinePOs
INSERT INTO #TempMaterialLinePOs
(
    OrderID,
    LineNumber,
    OrderItemId,
    P2PLineItemId,
    Quantity,
    UnitPrice
)
SELECT DISTINCT
    POI.OrderId,
    POI.LineNumber,
    POI.OrderItemId,
    POI.P2PLineItemID,
    POI.Quantity,
    POI.UnitPrice
FROM #OrderIds AS Ids WITH (NOLOCK)
    INNER JOIN DM_Documents AS D WITH (NOLOCK)
        ON Ids.DocumentCode = D.DocumentCode
    INNER JOIN P2P_OrderItems AS POI WITH (NOLOCK)
        ON POI.OrderId = Ids.DocumentCode
    INNER JOIN P2P_Orders AS P WITH (NOLOCK)
        ON D.DocumentCode = P.OrderId
WHERE POI.ItemExtendedType = 1
      AND POI.ClosingOrderStatus <> 124
      --AND POI.IsCloseForReceiving = 0 /*TSO : commented on 01/25 for order#0061020043*/
      AND POI.IsDeleted = 0
      AND POI.ItemStatus <> 121
      AND D.IsDeleted = 0;

-- Drop and create temporary table for line total value of material purchase orders
DROP TABLE IF EXISTS #LineTotalValueOfMaterialPOs;
CREATE TABLE #LineTotalValueOfMaterialPOs
(
    Orderid BIGINT,
    LineNumber INT,
    Quantity DECIMAL(18, 6),
    UnitPrice DECIMAL(18, 6),
    CurrentOrderLineTotal DECIMAL(18, 6),
    P2PLineItemId BIGINT
);

-- Insert distinct values into #LineTotalValueOfMaterialPOs
INSERT INTO #LineTotalValueOfMaterialPOs
(
    OrderId,
    LineNumber,
    Quantity,
    UnitPrice,
    CurrentOrderLineTotal,
    P2PLineItemId
)
SELECT DISTINCT
    TML.Orderid,
    TML.LineNumber,
    TML.Quantity,
    TML.UnitPrice,
    TML.UnitPrice * TML.Quantity AS CurrentOrderLineTotal,
    TML.P2PLineItemId
FROM #TempMaterialLinePOs AS TML WITH (NOLOCK);

-- Drop and create temporary table for receipt lines
DROP TABLE IF EXISTS #ReceiptLines;
CREATE TABLE #ReceiptLines
(
    OrderId BIGINT,
    P2PLineItemId BIGINT,
    TotalAcceptedQuantity DECIMAL(18, 6)
);

-- Insert distinct values into #ReceiptLines
INSERT INTO #ReceiptLines
(
    OrderId,
    P2PLineItemId,
    TotalAcceptedQuantity
)
SELECT DISTINCT
    LTP.OrderId,
    LTP.P2PLineItemId,
    SUM(PRI.AcceptedQuantity) AS TotalAcceptedQuantity
FROM P2P_ReceiptItems AS PRI WITH (NOLOCK)
    INNER JOIN #LineTotalValueOfMaterialPOs AS LTP WITH (NOLOCK)
        ON PRI.P2PLineItemId = LTP.P2PLineItemId
    INNER JOIN P2P_Receipts AS PR WITH (NOLOCK)
        ON PRI.ReceiptId = PR.ReceiptId
    INNER JOIN DM_Documents AS D WITH (NOLOCK)
        ON PR.ReceiptId = D.DocumentCode
    INNER JOIN P2P_OrderReceiptMapping AS orm WITH (NOLOCK)
        ON ORM.ReceiptId = D.DocumentCode
           AND LTP.OrderId = ORM.OrderId
WHERE ISNULL(D.DocumentStatus, 0) = 175
      AND PRI.ItemStatus <> 121
      AND D.IsDeleted = 0
      AND PRI.IsDeleted = 0
      AND PR.IsDeleted = 0
GROUP BY LTP.P2PLineItemId,
         LTP.OrderId;

-- Update DifferenceQuantity and TotalAcceptedAmount in #TempMaterialLinePOs
UPDATE LTP
SET DifferenceQuantity = ISNULL(LTP.Quantity, 0) - (ISNULL(RL.TotalAcceptedQuantity, 0)),
    TotalAcceptedAmount = (ISNULL(RL.TotalAcceptedQuantity, 0) * ISNULL(LTP.UnitPrice, 0))
FROM #TempMaterialLinePOs AS LTP WITH (NOLOCK)
    LEFT JOIN #ReceiptLines AS RL WITH (NOLOCK)
        ON LTP.P2PLineItemId = RL.P2PLineItemId
           AND LTP.OrderID = RL.OrderID
    LEFT JOIN #CreditMemoItems AS CI WITH (NOLOCK)
        ON CI.OrderItemId = LTP.OrderItemId;

-- Update DifferenceQuantity and TotalAcceptedAmount in #TempMaterialLinePOs_All
UPDATE LTP
SET DifferenceQuantity = ISNULL(LTP.Quantity, 0) - (ISNULL(RL.TotalAcceptedQuantity, 0)),
    TotalAcceptedAmount = (ISNULL(RL.TotalAcceptedQuantity, 0) * ISNULL(LTP.UnitPrice, 0))
FROM #TempMaterialLinePOs_All AS LTP WITH (NOLOCK)
    LEFT JOIN #ReceiptLines_All AS RL WITH (NOLOCK)
        ON LTP.P2PLineItemId = RL.P2PLineItemId
           AND LTP.OrderID = RL.OrderID
    LEFT JOIN #CreditMemoItems AS CI WITH (NOLOCK)
        ON CI.OrderItemId = LTP.OrderItemId;

-- Drop and create table for final result of material lines
DROP TABLE IF EXISTS #FinalResultForMaterialLines;
CREATE TABLE #FinalResultForMaterialLines
(
    OrderiD BIGINT,
    P2PLIneItemId BIGINT,
    LineNumber INT,
    ActualOrderLineTotal DECIMAL(18, 6),
    Quantity DECIMAL(18, 6),
    CurrentOrderLineTotal DECIMAL(18, 6),
    OrderitemID BIGINT,
	MUnitPrice  DECIMAL(18, 6) /*TSO :added on 01/21 */
);

-- Insert into #FinalResultForMaterialLines
INSERT INTO #FinalResultForMaterialLines
(
    OrderID,
    P2PLineItemId,
    LineNumber,
    ActualOrderLineTotal,
    Quantity,
    CurrentOrderLineTotal,
    OrderItemID
	,MUnitPrice  /*TSO :added on 01/21 */
)
SELECT TML.OrderID,
       TML.P2PLineItemId,
       TML.LineNumber,
       ISNULL(TML.TotalAcceptedAmount, 0),
       ISNULL(TML.DifferenceQuantity, 0),
       LTP.CurrentOrderLineTotal - ISNULL(TML.TotalAcceptedAmount, 0),
       TML.OrderItemID
	   ,TML.UnitPrice AS MUnitPrice
FROM #TempMaterialLinePOs AS TML WITH (NOLOCK)
    INNER JOIN #LineTotalValueOfMaterialPOs AS LTP WITH (NOLOCK)
        ON TML.P2PLineItemId = LTP.P2PLineItemId
           AND LTP.OrderId = TML.OrderID
WHERE TML.DifferenceQuantity > 0; /*TSO : updated on 01-21 */

-- Drop and create table for fully received material lines
DROP TABLE IF EXISTS #FinalResultForMaterialLinesFullyReceived;
CREATE TABLE #FinalResultForMaterialLinesFullyReceived
(
    OrderiD BIGINT,
    P2PLIneItemId BIGINT,
    LineNumber INT,
    ActualOrderLineTotal DECIMAL(18, 6),
    Quantity DECIMAL(18, 6),
    CurrentOrderLineTotal DECIMAL(18, 6),
    OrderItemID BIGINT
);

-- Insert into #FinalResultForMaterialLinesFullyReceived
INSERT INTO #FinalResultForMaterialLinesFullyReceived
(
    OrderID,
    P2PLineItemId,
    LineNumber,
    ActualOrderLineTotal,
    Quantity,
    CurrentOrderLineTotal,
    OrderItemID
)
SELECT TML.OrderID,
       TML.P2PLineItemId,
       TML.LineNumber,
       ISNULL(TML.TotalAcceptedAmount, 0),
       ISNULL(TML.DifferenceQuantity, 0),
       LTP.CurrentOrderLineTotal - ISNULL(TML.TotalAcceptedAmount, 0),
       TML.OrderItemID
FROM
(SELECT DISTINCT OrderID FROM #TempMaterialLinePOs) AS po
    INNER JOIN #TempMaterialLinePOs_All AS tml WITH (NOLOCK)
        ON tml.OrderID = po.OrderID
    INNER JOIN #LineTotalValueOfMaterialPOs_ALL AS LTP WITH (NOLOCK)
        ON TML.P2PLineItemId = LTP.P2PLineItemId
           AND LTP.OrderId = TML.OrderID
WHERE TML.DifferenceQuantity > 0;	/*TSO : updated on 01-21 */

----------------------------------- Order Material Lines Details Ended -----------------------------------

----------------------------------- Expired Contract Details Started -----------------------------------

-- Drop the temporary table if it already exists
DROP TABLE IF EXISTS #Expiredcontract;

-- Create the #Expiredcontract table
CREATE TABLE #Expiredcontract
(
    ContractNumber NVARCHAR(500),
    DateExpiry DATETIME
);

-- Insert distinct records into the #Expiredcontract table
INSERT INTO #Expiredcontract
SELECT DISTINCT
    DMS.DocumentNumber,
    EC1.DateExpiry
FROM DM_Documents AS DMS WITH (NOLOCK)
    INNER JOIN P2P_OrderItems AS POI WITH (NOLOCK)
        ON POI.ContractNo = DMS.DocumentNumber
    INNER JOIN EC_ContractDetails AS EC1 WITH (NOLOCK)
        ON EC1.DocumentCode = DMS.DocumentCode
    INNER JOIN #OrderIds AS ORD WITH (NOLOCK)
        ON POI.OrderId = ORD.DocumentCode
WHERE DMS.IsBuyerVisible = 1
      AND DMS.IsDeleted = 0
      AND DMS.DocumentTypeCode = 5
      AND POI.ContractNo IS NOT NULL
      AND DMS.DocumentStatus IN ( 71, 83, 125 );

----------------------------------- Expired Contract Details Ended -----------------------------------

--------------------------------- Order Service Line Details started -----------------------------------

-- Drop and create temporary table for service line purchase orders
DROP TABLE IF EXISTS #TempServiceLinePOs;
CREATE TABLE #TempServiceLinePOs
(
    OrderID BIGINT,
    LineNumber INT,
    OrderItemId BIGINT,
    P2PLineItemId BIGINT,
    Quantity DECIMAL(18, 6),
    UnitPrice DECIMAL(18, 6),
    DateDifference INT,
    DifferenceAmount DECIMAL(36, 18)
        DEFAULT 0,
    TotalReceivedAmount DECIMAL(36, 18)
        DEFAULT 0
);

-- Insert distinct values into #TempServiceLinePOs
INSERT INTO #TempServiceLinePOs
(
    OrderID,
    LineNumber,
    OrderItemId,
    P2PLineItemId,
    Quantity,
    UnitPrice,
    DateDifference
)
SELECT DISTINCT
    POI.OrderId,
    POI.LineNumber,
    POI.OrderItemId,
    POI.P2PLineItemID,
    POI.Quantity,
    POI.UnitPrice,
    DATEDIFF(   DAY,
                GETDATE(),
                CASE
                    WHEN ISNULL(POI.ContractNo, '') = '' THEN
                        POI.EndDate
                    ELSE
                        ContractDoc.DateExpiry
                END
            ) AS DateDifference
FROM #OrderIds AS PO WITH (NOLOCK)
    INNER JOIN DM_Documents AS D WITH (NOLOCK)
        ON D.DocumentCode = PO.DocumentCode
    INNER JOIN P2P_OrderItems AS POI WITH (NOLOCK)
        ON POI.OrderId = D.DocumentCode
    INNER JOIN P2P_Orders AS P WITH (NOLOCK)
        ON D.DocumentCode = P.OrderId
    LEFT JOIN #Expiredcontract AS ContractDoc WITH (NOLOCK)
        ON ContractDoc.ContractNumber = POI.ContractNo
WHERE POI.ItemExtendedType IN ( 2, 3 )
      AND POI.ClosingOrderStatus <> 124
      AND POI.IsCloseForInvoicing = 0
      AND POI.IsDeleted = 0
      AND POI.ItemStatus <> 121
      AND D.IsDeleted = 0;

-- Drop and create temporary table for line total value of service purchase orders
DROP TABLE IF EXISTS #LineTotalValueOfServicePOs;
CREATE TABLE #LineTotalValueOfServicePOs
(
    OrderId BIGINT,
    LineNumber INT,
    Quantity DECIMAL(18, 6),
    UnitPrice DECIMAL(18, 6),
    CurrentOrderLineTotal DECIMAL(18, 6),
    P2PLineItemId BIGINT
);

-- Insert distinct values into #LineTotalValueOfServicePOs
INSERT INTO #LineTotalValueOfServicePOs
(
    OrderId,
    LineNumber,
    Quantity,
    UnitPrice,
    CurrentOrderLineTotal,
    P2PLineItemId
)
SELECT DISTINCT
    TML.OrderId,
    TML.LineNumber,
    TML.Quantity,
    TML.UnitPrice,
    (TML.UnitPrice * TML.Quantity) AS CurrentOrderLineTotal,
    TML.P2PLineItemId
FROM #TempServiceLinePOs AS TML WITH (NOLOCK);

-- Drop and create temporary table for approved service confirmation items
DROP TABLE IF EXISTS #approvedscitems;
CREATE TABLE #approvedscitems
(
    p2plineitemid BIGINT,
    approved DECIMAL(18, 6)
);

-- Insert approved values into #approvedscitems
INSERT INTO #approvedscitems
(
    p2plineitemid,
    approved
)
SELECT SCI.P2PLineItemId,
       CASE
           WHEN SCI.ItemExtendedType = 2 THEN
               SUM(SCI.Quantity * SCI.UnitPrice)
           ELSE
               SUM(SCI.Quantity)
       END AS Approved
FROM p2p_serviceconfirmationitems AS SCI WITH (NOLOCK)
    INNER JOIN dm_documents AS D WITH (NOLOCK)
        ON SCI.serviceconfirmationid = D.documentcode
           AND D.documentstatus = 22
           AND SCI.isdeleted = 0
           AND SCI.itemlevel = 1
    INNER JOIN P2P_OrderServiceConfirmationMapping AS mapp WITH (NOLOCK)
        ON mapp.ServiceConfirmationId = SCI.ServiceConfirmationId
    INNER JOIN #OrderIds AS TEMP WITH (NOLOCK)
        ON mapp.OrderId = TEMP.DocumentCode
WHERE SCI.isdeleted = 0
      AND D.IsDeleted = 0
GROUP BY SCI.p2plineitemid,
         SCI.itemextendedtype;

-- Drop and create temporary table for service confirmation line items
DROP TABLE IF EXISTS #scLineItems;
CREATE TABLE #scLineItems
(
    OrderId BIGINT,
    OrderItemID BIGINT,
    Ordered DECIMAL(18, 6),
    Approved DECIMAL(18, 6),
    CreditAmount DECIMAL(18, 6),
    Remaining DECIMAL(18, 6)
);

-- Insert calculated values into #scLineItems
INSERT INTO #scLineItems
(
    OrderId,
    OrderItemID,
    Ordered,
    Approved,
    CreditAmount,
    Remaining
)
SELECT DISTINCT
    SC.OrderId,
    SC.OrderItemID,
    SC.Ordered,
    SC.Approved,
    SC.CreditAmount,
    SC.Remaining
FROM
(
    SELECT O.OrderId AS OrderId,
           orditems.OrderItemID AS OrderItemID,
           CASE
               WHEN orditems.itemextendedtype = 2 THEN
                   CASE
                       WHEN ISNULL(orditems.OverallItemLimit, 0) > ISNULL(orditems.quantity * orditems.unitprice, 0) THEN
                           ISNULL(orditems.OverallItemLimit, 0)
                       ELSE
                           ISNULL(orditems.quantity * orditems.unitprice, 0)
                   END
               ELSE
                   CASE
                       WHEN ISNULL(orditems.OverallItemLimit, 0) > ISNULL(orditems.quantity, 0) THEN
                           ISNULL(orditems.OverallItemLimit, 0)
                       ELSE
                           ISNULL(orditems.quantity, 0)
                   END
           END AS Ordered,
           ISNULL(ASCI.Approved, 0) AS Approved,
           ISNULL(CREDITMEMO.CreditAmount, 0) AS CreditAmount,
           CASE
               WHEN orditems.ItemExtendedType = 2 THEN
                   CASE
                       WHEN ISNULL(orditems.OverallItemLimit, 0) > ISNULL(orditems.quantity * orditems.unitprice, 0) THEN
                           CASE
                               WHEN (orditems.OverallItemLimit - ISNULL(ASCI.Approved, 0)
                                     + ISNULL(CREDITMEMO.CreditAmount, 0)
                                    ) > 0 THEN
           (orditems.OverallItemLimit - ISNULL(ASCI.Approved, 0) + ISNULL(CREDITMEMO.CreditAmount, 0))
                               ELSE
                                   0
                           END
                       ELSE
                           CASE
                               WHEN ((orditems.UnitPrice * orditems.Quantity) - ISNULL(ASCI.Approved, 0)
                                     + ISNULL(CREDITMEMO.CreditAmount, 0)
                                    ) > 0 THEN
           ((orditems.Unitprice * orditems.Quantity) - ISNULL(ASCI.Approved, 0) + ISNULL(CREDITMEMO.CreditAmount, 0))
                               ELSE
                                   0
                           END
                   END
               ELSE
                   CASE
                       WHEN ISNULL(orditems.OverallItemLimit, 0) > ISNULL(orditems.quantity, 0) THEN
                           CASE
                               WHEN (orditems.OverallItemLimit - ISNULL(ASCI.Approved, 0)
                                     + ISNULL(CREDITMEMO.CreditAmount, 0)
                                    ) > 0 THEN
           (orditems.OverallItemLimit - ISNULL(ASCI.Approved, 0) + ISNULL(CREDITMEMO.CreditAmount, 0))
                               ELSE
                                   0
                           END
                       ELSE
                           CASE
                               WHEN (orditems.Quantity - ISNULL(ASCI.Approved, 0) + ISNULL(CREDITMEMO.CreditAmount, 0)) > 0 THEN
           (orditems.Quantity - ISNULL(ASCI.Approved, 0) + ISNULL(CREDITMEMO.CreditAmount, 0))
                               ELSE
                                   0
                           END
                   END
           END AS Remaining
    FROM #TempServiceLinePOs AS O WITH (NOLOCK)
        INNER JOIN p2p_orderitems AS orditems WITH (NOLOCK)
            ON orditems.OrderId = O.OrderID
        INNER JOIN P2P_ServiceConfirmation AS S WITH (NOLOCK)
            ON S.OrderId = O.OrderID
        INNER JOIN dm_documents AS D WITH (NOLOCK)
            ON S.ServiceConfirmationId = D.DocumentCode
               AND D.documentstatus = 22
               AND D.IsDeleted = 0
        INNER JOIN P2P_ServiceConfirmationItems AS SCI WITH (NOLOCK)
            ON SCI.ServiceConfirmationId = S.ServiceConfirmationId
               AND SCI.isdeleted = 0
               AND orditems.P2PLineItemID = SCI.P2PLineItemId
        LEFT OUTER JOIN #approvedscitems AS ASCI WITH (NOLOCK)
            ON SCI.P2PLineItemId = ASCI.P2PLineItemId
        LEFT JOIN #CreditMemoItems AS CREDITMEMO WITH (NOLOCK)
            ON CREDITMEMO.OrderItemid = orditems.OrderItemID
) AS SC;

-- Update DifferenceQuantity and TotalAcceptedAmount in #TempServiceLinePOs
UPDATE LTP
SET DifferenceAmount = ISNULL(LTP.UnitPrice, 0) - ISNULL(RL.Approved, 0),
    TotalReceivedAmount = ISNULL(RL.Approved, 0)
FROM #TempServiceLinePOs AS LTP WITH (NOLOCK)
    LEFT JOIN #scLineItems AS RL WITH (NOLOCK)
        ON LTP.OrderItemId = RL.OrderItemID
           AND LTP.OrderID = RL.OrderID
    LEFT JOIN #CreditMemoItems AS CI WITH (NOLOCK)
        ON CI.OrderItemid = LTP.OrderItemId;

-- Drop and create table for final result of service lines
DROP TABLE IF EXISTS #FinalResultForServiceLines;
CREATE TABLE #FinalResultForServiceLines
(
    OrderID BIGINT,
    P2PLineItemId BIGINT,
    LineNumber INT,
    ActualOrderLineTotal DECIMAL(18, 6),
    Quantity DECIMAL(18, 6),
    CurrentOrderLineTotal DECIMAL(18, 6),
    OrderItemId BIGINT
	,SUnitPrice DECIMAL(18, 6) /*TSO:added on 01/21 */
);

-- Insert into #FinalResultForServiceLines
INSERT INTO #FinalResultForServiceLines
(
    OrderID,
    P2PLineItemId,
    LineNumber,
    ActualOrderLineTotal,
    Quantity,
    CurrentOrderLineTotal,
    OrderItemId
	,SUnitPrice
	
)
SELECT TML.OrderID,
       TML.P2PLineItemId,
       TML.LineNumber,
       TML.TotalReceivedAmount,
       1 AS Quantity,
       LTP.CurrentOrderLineTotal - TML.TotalReceivedAmount,
       TML.OrderItemId
	   ,LTP.CurrentOrderLineTotal - TML.TotalReceivedAmount  AS SUnitPrice /*added on 01/21 */
FROM #TempServiceLinePOs AS TML WITH (NOLOCK)
    INNER JOIN #LineTotalValueOfServicePOs AS LTP WITH (NOLOCK)
        ON TML.P2PLineItemId = LTP.P2PLineItemId
           AND LTP.OrderId = TML.OrderID
--WHERE TML.DifferenceAmount > 0
-- OR (
-- TML.DifferenceAmount = 0
-- AND TML.DateDifference > -180
-- );

--------------------------------- Order Service Line Details Ended -----------------------------------

------------------------------ Legacy Order Amount Calculation Started -------------------------------

-- Drop and create the table for legacy order amounts
DROP TABLE IF EXISTS #legacyOrderAmount;

SELECT DISTINCT
    COALESCE(FML.P2PLIneItemId, FSL.P2PLIneItemId) AS P2PLIneItemId,
    ISNULL(FML.CurrentOrderLineTotal, FSL.CurrentOrderLineTotal) AS CurrentOrderLineTotal,
    ISNULL(FML.OrderiD, FSL.OrderiD) AS OrderId,
    ISNULL(FML.Quantity, FSL.Quantity) AS Quantity
	,FSL.SUnitPrice AS UnitPrice /* TSO: updated on  01/21 */
INTO #LegacyOrderAmount
FROM #FinalResultForMaterialLines AS FML
    FULL OUTER JOIN #FinalResultForServiceLines AS FSL
        ON FML.OrderiD = FSL.OrderiD;

------------------------------ Legacy Order Amount Calculation Ended -------------------------------

----------------------------------- Order Ids Started ---------------------------------------------
-- Drop and create the table for draft orders
DROP TABLE IF EXISTS #DraftOrders;
CREATE TABLE #DraftOrders
(
    OrderId BIGINT,
    OrderItemId BIGINT
);

-- Insert draft orders into #DraftOrders
INSERT INTO #DraftOrders
(
    OrderId,
    OrderItemId
)
SELECT DM.DocumentCode AS OrderId,
       ITEMS.OrderItemId
FROM DM_Documents AS DM WITH (NOLOCK)
    INNER JOIN P2P_Orders AS PO WITH (NOLOCK)
        ON PO.OrderID = DM.DocumentCode
    INNER JOIN P2P_OrderItems AS ITEMS WITH (NOLOCK)
        ON ITEMS.OrderId = PO.OrderID
    INNER JOIN DM_DocumentBU AS DBU WITH (NOLOCK)
        ON DBU.DocumentCode = PO.OrderID
WHERE DM.DocumentStatus = 1
      AND DM.IsDeleted = 0
      AND ITEMS.IsDeleted = 0
      AND DATEDIFF(DAY, DM.DateCreated, GETDATE()) < 60
      AND PO.OrderSource IN ( 1, 2, 7 )
      AND DBU.BUCode IN (  745471, 853462, 1218826, 2338289,1084116,11096063,11096059,11096060,11096061,11096064,11096065 );

-- Drop and create the table for the final order list
DROP TABLE IF EXISTS #FinalOrderList;
CREATE TABLE #FinalOrderList
(
    OrderID BIGINT,
    OrderItemId BIGINT
);

-- Insert data into #FinalOrderList
INSERT INTO #FinalOrderList
(
    OrderID,
    OrderItemId
)
SELECT OrderID,
       OrderItemId
FROM #FinalResultForMaterialLinesFullyReceived
UNION ALL
SELECT OrderID,
       OrderItemId
FROM #FinalResultForServiceLines
UNION ALL
SELECT OrderID,
       OrderItemId
FROM #DraftOrders;

----------------------------------- Order Ids Ended -----------------------------------------------

-------------------------------- PO External TAX Migration Data Started ----------------------------------

SELECT DISTINCT
    DM.DocumentNumber AS [OrderNumber (UniqueKey)*] ,--taxes.TaxBase ,poi.ItemExtendedType,loa.CurrentOrderLineTotal,poi.Quantity, (ISNULL(LOA.CurrentOrderLineTotal, 0) * ISNULL(POI.Quantity, 0)) * ISNULL(taxes.TaxRate, 0),
    POI.LineNumber AS [OrderLineNumber*],
    ISNULL(taxes.TaxDescription, '') AS [TaxDescription*],
    ISNULL(Taxes.AuthorityName, '') AS [AuthorityName*],
    ISNULL(Taxes.TaxCode, '') AS [TaxCode*],
    ISNULL(taxes.TaxType, '') AS [TaxType*],
    CASE
        WHEN POI.ItemExtendedType IN ( 2, 3 )
             AND ISNULL(LOA.CurrentOrderLineTotal, 0) = 0 THEN
    (ISNULL(LOA.CurrentOrderLineTotal, 0) * ISNULL(POI.Quantity, 0)) * ISNULL(taxes.TaxRate, 0)
        WHEN POI.ItemExtendedType IN ( 2, 3 )
             AND ISNULL(LOA.CurrentOrderLineTotal, 0) > 0 THEN
    (ISNULL(LOA.CurrentOrderLineTotal, 0) * ISNULL(POI.Quantity, 0))* ISNULL(taxes.TaxRate, 0)
        ELSE
    (ISNULL(POI.UnitPrice, 0) * ISNULL(POI.Quantity, 0)) * ISNULL(taxes.TaxRate, 0)
    END AS [TaxValue*],
    ISNULL(taxes.TaxRate, 0) AS [TaxRate*],
    CASE
        WHEN POI.ItemExtendedType IN ( 2, 3 )
             AND ISNULL(LOA.CurrentOrderLineTotal, 0) = 0 THEN
            (ISNULL(LOA.CurrentOrderLineTotal, 0) * ISNULL(FSL.Quantity, 0)) 
        WHEN POI.ItemExtendedType IN ( 2, 3 )
             AND ISNULL(LOA.CurrentOrderLineTotal, 0) > 0 THEN
            (ISNULL(LOA.CurrentOrderLineTotal, 0) * ISNULL(FSL.Quantity, 0))* ISNULL(taxes.TaxRate, 0)/*TSO: 01/25 */
		WHEN POI.ItemExtendedType IN ( 1 ) THEN
			taxes.TaxBase
        ELSE
              (ISNULL(POI.UnitPrice, 0) * ISNULL(FML.Quantity, 0))
    END AS [TaxBase*],
    ISNULL(taxes.AppliedTaxValue, 0) AS [AppliedTaxValue*],
    ISNULL(taxes.AppliedTaxRate, 0) AS [AppliedTaxRate*],
    ISNULL(taxes.AuthorityType, '') AS [AuthorityType*],
    ISNULL(taxes.IsTaxOverriden, 0) AS [IsTaxOverriden*],
    ISNULL(taxes.ExternalAddressId, 0) AS [ExternalAddressId*]
FROM #OrderIds AS OrderIds
    INNER JOIN DM_Documents AS DM WITH (NOLOCK)
        ON OrderIds.DocumentCode = DM.DocumentCode
    INNER JOIN #FinalOrderList AS PO_List WITH (NOLOCK)
        ON PO_List.Orderid = DM.DocumentCode
    INNER JOIN P2P_OrderItems AS POI WITH (NOLOCK)
        ON POI.OrderId = DM.DocumentCode
           AND PO_List.Orderitemid = POI.OrderItemID
    INNER JOIN P2P_Orders AS PO WITH (NOLOCK)
        ON PO.OrderID = POI.OrderId
    INNER JOIN P2P_OrderExternalTaxes AS taxes WITH (NOLOCK)
        ON taxes.OrderItemId = POI.OrderItemID
           AND taxes.IsDeleted = 0
    LEFT JOIN #LegacyOrderAmount AS LOA WITH (NOLOCK)
        ON LOA.OrderId = PO.OrderID
           AND LOA.P2PLIneItemId = POI.P2PLineItemID
    LEFT JOIN #FinalResultForMaterialLines AS FML WITH (NOLOCK)
        ON FML.OrderitemID = POI.OrderItemID
           AND FML.P2PLIneItemId = POI.P2PLineItemID
    LEFT JOIN #FinalResultForServiceLines AS FSL WITH (NOLOCK)
        ON FSL.OrderitemID = POI.OrderItemID
           AND FSL.P2PLIneItemId = POI.P2PLineItemID
WHERE (
          PO.IsCloseForReceiving = 0
          OR PO.IsCloseForInvoicing = 0
      )
      AND POI.IsDeleted = 0
      AND DM.IsDeleted = 0
      AND DM.DocumentStatus NOT IN ( 121, 141 )
      AND PO.ClosingOrderStatus <> 124
      AND POI.ItemStatus <> 121
      AND (
              POI.IsCloseForReceiving = 0
              OR PO.IsCloseForInvoicing = 0
          )
      AND (
              PO.OrderSource IN ( 1, 2, 7 )
              OR (
                     PO.OrderSource = 5
                     AND DM.DocumentStatus NOT IN ( 1, 21, 24 )
                 )
          )
ORDER BY DM.DocumentNumber,
         POI.LineNumber;

-------------------------------- PO External Tax Migration Data Ended ----------------------------------