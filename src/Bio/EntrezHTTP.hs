{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Arrows #-}

-- | Interface for the NCBI Entrez REST webservice
module Bio.EntrezHTTP (module Bio.EntrezHTTPData,
                       EntrezHTTPQuery(..),
                       entrezHTTP,
                       readEntrezTaxonSet,
                       readEntrezSimpleTaxons,
                       readEntrezParentIds,
                       readEntrezSummaries,
                      ) where

import Network.HTTP.Conduit    
import qualified Data.ByteString.Lazy.Char8 as L8    
import Text.XML.HXT.Core
import Network
import Data.Maybe
import Bio.EntrezHTTPData
import Bio.TaxonomyData (Rank)
      
-- | Send query and parse return XML 
startSession :: String -> String -> String -> IO String
startSession program' database' query' = do
  requestXml <- withSocketsDo
      $ sendQuery program' database' query'
  let requestXMLString = L8.unpack requestXml
  return requestXMLString

-- | Send query and return response XML
sendQuery :: String -> String -> String -> IO L8.ByteString
sendQuery program' database' query' = simpleHttp ("http://eutils.ncbi.nlm.nih.gov/entrez/eutils/"++ program' ++ ".fcgi?" ++ "db=" ++ database' ++ "&" ++ query')         

-- |
entrezHTTP :: EntrezHTTPQuery -> IO String
entrezHTTP (EntrezHTTPQuery program' database' query') = do
  let defaultProgram = "summary"
  let defaultDatabase = "nucleotide"                  
  let selectedProgram = fromMaybe defaultProgram program'
  let selectedDatabase = fromMaybe defaultDatabase database'  
  startSession selectedProgram selectedDatabase query'

-- | Read entrez fetch for taxonomy database into a simplyfied datatype 
-- Result of e.g: http://eutils.ncbi.nlm.nih.
readEntrezTaxonSet :: String -> [Taxon]
readEntrezTaxonSet input = runLA (xreadDoc >>> parseEntrezTaxon) input

parseEntrezTaxon :: ArrowXml a => a XmlTree Taxon
parseEntrezTaxon = getChildren >>> atTag "Taxon" >>>
  proc entrezTaxon -> do
  _taxId <- atTag "TaxId" >>> getChildren >>> getText -< entrezTaxon
  _scientificName <- atTag "ScientificName" >>> getChildren >>> getText -< entrezTaxon
  _parentTaxId <- atTag "ParentTaxId" >>> getChildren >>> getText -< entrezTaxon
  _rank <- atTag "Rank" >>> getChildren >>> getText -< entrezTaxon
  _divison <- atTag "Division" >>> getChildren >>> getText -< entrezTaxon
  _geneticCode <- parseTaxonGeneticCode  -< entrezTaxon
  _mitoGeneticCode  <- parseTaxonMitoGeneticCode -< entrezTaxon
  _linage <- atTag "Linage" >>> getChildren >>> getText -< entrezTaxon
  _linageEx <- parseTaxonLinageEx -< entrezTaxon
  _createDate <- atTag "CreateDate" >>> getChildren >>> getText -< entrezTaxon
  _updateDate <- atTag "UpdateDate" >>> getChildren >>> getText -< entrezTaxon
  _pubDate <- atTag "PubDate" >>> getChildren >>> getText -< entrezTaxon
  returnA -< Taxon {
    taxId = read _taxId :: Int,
    scientificName = _scientificName,
    parentTaxId = read _parentTaxId :: Int,
    rank = read _rank :: Rank,
    division = _divison,
    geneticCode = _geneticCode,
    mitoGeneticCode = _mitoGeneticCode,
    lineage = _linage,
    lineageEx = _linageEx,
    createDate = _createDate,
    updateDate = _updateDate,
    pubDate = _pubDate
    }
  
parseTaxonGeneticCode :: ArrowXml a => a XmlTree GeneticCode
parseTaxonGeneticCode = getChildren >>> atTag "GeneticCode" >>>
  proc geneticcode -> do
  _gcId <- atTag "GCId" >>> getChildren >>> getText -< geneticcode
  _gcName <- atTag "GCName" >>> getChildren >>> getText -< geneticcode
  returnA -< GeneticCode {
    gcId = read _gcId :: Int,
    gcName = _gcName
    }

parseTaxonMitoGeneticCode :: ArrowXml a => a XmlTree MitoGeneticCode
parseTaxonMitoGeneticCode = getChildren >>> atTag "GeneticCode" >>>
  proc mitogeneticcode -> do
  _mgcId <- atTag "MGCId" >>> getChildren >>> getText -< mitogeneticcode
  _mgcName <- atTag "MGCName" >>> getChildren >>> getText -< mitogeneticcode
  returnA -< MitoGeneticCode {
    mgcId = read _mgcId :: Int,
    mgcName = _mgcName
    }

parseTaxonLinageEx :: ArrowXml a => a XmlTree [LineageTaxon]
parseTaxonLinageEx = getChildren >>> atTag "LineageEx" >>>
  proc linageEx -> do
  _linageEx <- listA parseLineageTaxon -< linageEx
  returnA -< _linageEx

parseLineageTaxon :: ArrowXml a => a XmlTree LineageTaxon
parseLineageTaxon = getChildren >>> atTag "Taxon" >>>
  proc lineageTaxon -> do
  _lineageTaxId <- atTag "TaxId" >>> getChildren >>> getText -< lineageTaxon
  _lineageScienticName <- atTag "ScientificName" >>> getChildren >>> getText -< lineageTaxon
  _lineageRank <- atTag "Rank" >>> getChildren >>> getText -< lineageTaxon
  returnA -< LineageTaxon {
    lineageTaxId = read _lineageTaxId :: Int, 
    lineageScienticName = _lineageScienticName,
    lineageRank = read _lineageRank :: Rank
    }

-- | Read entrez fetch for taxonomy database into a simplyfied datatype 
-- Result of e.g: http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=taxonomy&id=1406860
readEntrezSimpleTaxons :: String -> [SimpleTaxon]
readEntrezSimpleTaxons input = runLA (xreadDoc >>> parseEntrezSimpleTaxons) input

parseEntrezSimpleTaxons :: ArrowXml a => a XmlTree SimpleTaxon
parseEntrezSimpleTaxons = getChildren >>> atTag "Taxon" >>>
  proc entrezSimpleTaxon -> do
  simple_TaxId <- atTag "TaxId" >>> getChildren >>> getText -< entrezSimpleTaxon
  simple_ScientificName <- atTag "ScientificName" >>> getChildren >>> getText -< entrezSimpleTaxon
  simple_ParentTaxId <- atTag "ParentTaxId" >>> getChildren >>> getText -< entrezSimpleTaxon
  simple_Rank <- atTag "Rank" >>> getChildren >>> getText -< entrezSimpleTaxon
  returnA -< SimpleTaxon {
    simpleTaxonTaxId = read simple_TaxId :: Int,
    simpleTaxonScientificName = simple_ScientificName,
    simpleTaxonParentTaxId = read simple_ParentTaxId :: Int,
    simpleTaxonRank = read simple_Rank :: Rank
    } 

readEntrezParentIds :: String -> [Int]
readEntrezParentIds input = runLA (xreadDoc >>> parseEntrezParentTaxIds) input

parseEntrezParentTaxIds :: ArrowXml a => a XmlTree Int
parseEntrezParentTaxIds = getChildren >>> atTag "Taxon" >>>
  proc entrezSimpleTaxon -> do
  simple_ParentTaxId <- atTag "ParentTaxId" >>> getChildren >>> getText -< entrezSimpleTaxon
  returnA -< read simple_ParentTaxId :: Int
    
-- | Read entrez summary from internal haskell string
readEntrezSummaries :: String -> [EntrezSummary]
readEntrezSummaries input = runLA (xreadDoc >>> parseEntrezSummaries) input

-- | Parse entrez summary result
parseEntrezSummaries :: ArrowXml a => a XmlTree EntrezSummary
parseEntrezSummaries = atTag "eSummaryResult" >>> 
  proc entrezSummary -> do
  document_Summaries <- listA parseEntrezDocSums -< entrezSummary
  returnA -< EntrezSummary {
    documentSummaries = document_Summaries
    }     

-- | 
parseEntrezDocSums :: ArrowXml a => a XmlTree EntrezDocSum
parseEntrezDocSums = atTag "DocSum" >>> 
  proc entrezDocSum -> do
  summary_Id <- atTag "Id" >>> getChildren >>> getText -< entrezDocSum
  summary_Items <- listA parseSummaryItems -< entrezDocSum
  returnA -< EntrezDocSum {
    summaryId = summary_Id,
    summaryItems = summary_Items
    } 

-- | 
parseSummaryItems :: ArrowXml a => a XmlTree SummaryItem
parseSummaryItems = atTag "Item" >>> 
  proc summaryItem -> do
  item_Name <- getAttrValue "Name" -< summaryItem
  item_Type <- getAttrValue "Type" -< summaryItem
  item_Content <- getText <<< getChildren -< summaryItem
  returnA -< SummaryItem {
    itemName = item_Name,
    itemType = item_Type,
    itemContent = item_Content
    } 

-- | gets all subtrees with the specified tag name
atTag :: ArrowXml a =>  String -> a XmlTree XmlTree
atTag tag = deep (isElem >>> hasName tag)
