package org.apache.lucene.search;

import java.io.IOException;
import java.net.ConnectException;
import java.util.Collections;
import java.util.Enumeration;
import java.util.Vector;

import org.apache.commons.codec.binary.Base64;
import org.apache.lucene.search.caches.PwaDateCache;
import org.apache.lucene.search.caches.PwaIndexStats;
import org.apache.lucene.search.features.*;
import org.apache.lucene.search.features.querydependent.*;
import org.apache.lucene.search.features.queryindependent.*;
import org.apache.lucene.search.features.temporal.*;
import org.apache.lucene.search.memcached.*;
import org.apache.lucene.document.Document;


/**
 * Scores ranking features
 * @author Miguel Costa
 */
public class PwaScorerFeatures {
	
	private final static String BOOST_LABEL="boost";	
	
	private final static String MEMCACHED_ADDRESSES="193.136.192.57:11111"; //memcached TODO parameterize
	//private final static String MEMCACHED_ADDRESSES="127.0.0.1:11211"; //membase
	private static Memcached memcache=null;
	private static int maxVersions;
	private static int maxSpan;	
	private static long minTimestamp;
	private static long maxTimestamp;
	
		
	/**
	 * Ranking model that computes score	 
	 * @param doc document identifier
	 * @param queryTimestamp timestamp when the query was submitted
	 * @param collector ranking features collector
	 * @param posmanagers query term position into the document 
	 * @param searcher searcher
	 * @param functions ranking functions 
	 * @return ranking score
	 */
	public static PwaScores score(int doc, long queryTimestamp, PwaRawFeatureCollector collector, Vector<PwaPositionsManager> posmanagers, Searcher searcher, PwaFunctionsWritable functions) throws IOException {		
		PwaScores scores=new PwaScores();		
		int nDocs=collector.getNumDocs();
		Vector<Integer> vecTfs;
		Vector<Integer> vecIdfs;
		int fieldLength;
		double fieldAvgLength;		
		Vector<Vector<Integer>> tfPerField=new Vector<Vector<Integer>>();
		Vector<Vector<Integer>> idfPerField=new Vector<Vector<Integer>>();
		Vector<Integer> nTermsPerField=new Vector<Integer>();	
		//Vector<Double> avgNTermsPerField=new Vector<Double>();
				
		Vector<Integer> sumVecTfs=null;
		Vector<Integer> sumVecIdfs=null;
		Integer sumFieldLength=new Integer(0);	
		Double sumfieldAvgLength=new Double(0);		
		
		int funct=0; // function index		
		String surl=null; // URL string 
				
		// query dependent features
		if (!collector.isEmpty()) {
			// term weight features
			for (int i=0;i<PwaIndexStats.FIELDS.length;i++) {				
				vecTfs=collector.getFieldTfs(PwaIndexStats.FIELDS[i]); // vector of all query terms	for tf per term
				vecIdfs=collector.getFieldIdfs(PwaIndexStats.FIELDS[i]); // vector of all query terms for idf per term		
				fieldLength=collector.getFieldLength(PwaIndexStats.FIELDS[i]);
				fieldAvgLength=collector.getFieldAvgLength(PwaIndexStats.FIELDS[i]);			
			
				if (functions.hasFunction(funct)) {
					float score=0;
					for (int j=0;j<vecTfs.size();j++) {	// for all terms					
						score+= vecTfs.get(j); 
					}
					scores.addScore(funct, score); // sum of the frequency of each term
				}
				funct++;								
				if (functions.hasFunction(funct)) {
					float score=0;
					for (int j=0;j<vecIdfs.size();j++) {	// for all terms					
						score+= vecIdfs.get(j); 
					}
					scores.addScore(funct, score); // sum of the inverse document frequency of each term
				}
				funct++;							
				if (functions.hasFunction(funct)) {
					scores.addScore(funct, fieldLength); // field length			
				}
				funct++;				
				if (functions.hasFunction(funct)) {
					scores.addScore(funct, (float)fieldAvgLength); // field average length			
				}
				funct++;								
				if (functions.hasFunction(funct)) {
					scores.addScore(funct, (new PwaTFxIDF(vecTfs,vecIdfs,fieldLength,nDocs)).score()); // "TFxIDF-"+PwaIndexStats.FIELDS[i] 					
				}
				funct++;
				if (functions.hasFunction(funct)) {
					scores.addScore(funct, (new PwaBM25(vecTfs,vecIdfs,fieldLength,fieldAvgLength,nDocs)).score()); // "BM25-"+PwaIndexStats.FIELDS[i]				
				}
				funct++;
														
				// add values to vectors for term weighting functions using all fields
				tfPerField.add(vecTfs);
				idfPerField.add(vecIdfs);
				nTermsPerField.add(fieldLength);					
				//avgNTermsPerField.add(fieldAvgLength);
				
				if (sumVecTfs==null) { // i==0
					sumVecTfs=(Vector<Integer>)vecTfs.clone();
					sumVecIdfs=(Vector<Integer>)vecIdfs.clone();
				}
				else {
					for (int j=0;j<vecTfs.size();j++) {
						sumVecTfs.set(j,sumVecTfs.get(j)+vecTfs.get(j));
						sumVecIdfs.set(j,sumVecIdfs.get(j)+vecIdfs.get(j));
					}
				}
				sumFieldLength+=fieldLength;
				sumfieldAvgLength+=fieldAvgLength;							
			}	
			// term weight features using all fields at once
			if (functions.hasFunction(funct)) {
				scores.addScore(funct, (new PwaTFxIDF(sumVecTfs,sumVecIdfs,sumFieldLength,nDocs)).score()); // "TFxIDF-" + all fields 					
			}
			funct++;
			if (functions.hasFunction(funct)) {
				scores.addScore(funct, (new PwaBM25(sumVecTfs,sumVecIdfs,sumFieldLength,sumfieldAvgLength,nDocs)).score()); // "BM25-" + all fields				
			}
			funct++;				
			if (functions.hasFunction(funct)) {				
				scores.addScore(funct, (new PwaLuceneSimilarity(tfPerField,idfPerField,nTermsPerField,nDocs)).score()); // Lucene + all fields
			}
			funct++;
			if (functions.hasFunction(funct)) {				
				scores.addScore(funct, (new PwaLuceneSimilarityNormalized(tfPerField,idfPerField,nTermsPerField,nDocs)).score()); // Lucene normalized + all fields
			}
			funct++;
			if (functions.hasFunction(funct)) {				
				scores.addScore(funct, (new PwaNutchSimilarity(tfPerField,idfPerField,nTermsPerField,nDocs)).score()); // Nutch + all fields
			}
			funct++;
			if (functions.hasFunction(funct)) {				
				scores.addScore(funct, (new PwaNutchSimilarityNormalized(tfPerField,idfPerField,nTermsPerField,nDocs)).score()); // Nutch normalized + all fields
			}
			funct++;

			// term distance features
			for (int i=0;i<PwaIndexStats.FIELDS.length;i++) { // or for (i=0;i<posmanagers.length;i++) {  // per field
				if (functions.hasFunction(funct) || functions.hasFunction(funct+1) || functions.hasFunction(funct+2)) {					
					if (posmanagers.size()>0) { 					
						posmanagers.get(i).computeDistances(doc);
						if (functions.hasFunction(funct)) {						
							scores.addScore(funct, (new PwaMinSpan(posmanagers.get(i).getMinSpanCovOrdered())).score()); // "MinSpanCovOrd-"+PwaIndexStats.FIELDS[i]
						}
						funct++;
						if (functions.hasFunction(funct)) {						
							scores.addScore(funct, (new PwaMinSpan(posmanagers.get(i).getMinSpanCovUnordered())).score()); // "MinSpanCovUnord-"+PwaIndexStats.FIELDS[i]
						}
						funct++;
						if (functions.hasFunction(funct)) {						
							scores.addScore(funct, (new PwaMinSpan(posmanagers.get(i).getMinPairDist())).score()); // "MinPairDist-"+PwaIndexStats.FIELDS[i]
						}
						funct++;
					}
					else {
						scores.addScore(funct,0);						
						scores.addScore(funct+1,0);						
						scores.addScore(funct+2,0);
						funct+=3;
					}
				}
				else {
					funct+=3;
				}
			}			
		}
		else {
			funct+=PwaIndexStats.FIELDS.length*6 + 6 + PwaIndexStats.FIELDS.length*3;
		}
								
        // query independent features
		if (functions.hasFunction(funct) || functions.hasFunction(funct+1) || functions.hasFunction(funct+2) || functions.hasFunction(funct+3) || functions.hasFunction(funct+4)) {										
			Document docMeta=searcher.doc(doc);				
			if (functions.hasFunction(funct)) {
				surl=docMeta.get("url");				
				scores.addScore(funct, (new PwaUrlDepth(surl)).score()); // "UrlDepth"				
			}
			funct++;				
			if (functions.hasFunction(funct)) {
				surl=docMeta.get("url");									
				scores.addScore(funct, (new PwaUrlSlashes(surl)).score()); // "PwaUrlSlashes"				
			}
			funct++;			
			if (functions.hasFunction(funct)) {
				surl=docMeta.get("url");									
				scores.addScore(funct, surl.length()); // "URLLength"				
			}
			funct++;								
			if (functions.hasFunction(funct)) {
				String sinlinks=docMeta.get("inlinks");
				scores.addScore(funct, Integer.parseInt(sinlinks)); // "Inlinks"				
			}
			funct++;
			if (functions.hasFunction(funct)) {
				String sinlinks=docMeta.get("inlinks");
				scores.addScore(funct, (new PwaLinInlinks(Integer.parseInt(sinlinks))).score()); // "LinInlinks"				
			}
			funct++;
			/* do not work properly
			if (functions.hasFunction(funct)) {
				String spagerank=docMeta.get("pagerank");
				boost=functions.getBoost(funct);
				score+= Float.parseFloat(spagerank) * boost; // "Pagerank"			
			}
			funct++;			
			if (functions.hasFunction(funct)) {
				String spagerank=docMeta.get("pagerank");
				boost=functions.getBoost(funct);
				score+= (new PwaLinPagerank(Float.parseFloat(spagerank))).score() * boost; // "LinPagerank"			
			}
			funct++;
			if (functions.hasFunction(funct)) {
				String sboost=docMeta.get("boost");
				boost=functions.getBoost(funct);
				score+= Float.parseFloat(sboost) * boost; // OPIC
			}
			funct++;
			*/
		}
		else {
			funct+=5;
		}								
		
		// temporal features - local timestamps
		if (functions.hasFunction(funct) || functions.hasFunction(funct+1) || functions.hasFunction(funct+2)) {
			PwaDateCache cache=new PwaDateCache(null); // already initialized
			long timestamp=cache.getTimestamp(doc);
			//long minTimestamp=cache.getMinTimestamp();
			//long maxTimestamp=cache.getMaxTimestamp();											
			
			if (functions.hasFunction(funct)) {		
				scores.addScore(funct, ((float)queryTimestamp) / PwaIRankingFunction.DAY_MILLISEC); // Query issue time in days
			}
			funct++;			
			if (functions.hasFunction(funct)) {
				scores.addScore(funct, (new PwaAge(timestamp,queryTimestamp)).score()); // Age in days from query issue time
			}
			funct++;				
			if (functions.hasFunction(funct)) {		
				scores.addScore(funct, ((float)timestamp) / PwaIRankingFunction.DAY_MILLISEC); // Version's timestamp in days
			}
			funct++;			
		}
		else {
			funct+=3;
		}
		
		// temporal features - global timestamps
		boolean temporalGlobalUsed=false;
		for (int i=funct; !temporalGlobalUsed && i<funct+9; i++) {
			if (functions.hasFunction(i)) {
				temporalGlobalUsed=true;
			}
		}		
		if (temporalGlobalUsed) {									
			PwaDateCache cache=new PwaDateCache(null); // already initialized
			long timestamp=cache.getTimestamp(doc);
			
			int nVersionsURL;				
			long minTimestampURL;
			long maxTimestampURL;						
			UrlRow row=null;
			
			try {
				if (memcache==null) {
					memcache=new Memcached(MEMCACHED_ADDRESSES); // [address1=127.0.0.1:8091] [address2] ... [addressn]
					maxVersions=(Integer)memcache.get(MemcachedTransactions.MAX_VERSIONS);
					maxSpan=(Integer)memcache.get(MemcachedTransactions.MAX_SPAN);
					int minDate=(Integer)memcache.get(MemcachedTransactions.MIN_DATE);
					minTimestamp=MemcachedTransactions.intToLongdate(minDate);
					int maxDate=(Integer)memcache.get(MemcachedTransactions.MAX_DATE);
					maxTimestamp=MemcachedTransactions.intToLongdate(maxDate);					
				}
				
				if (surl==null) {
					Document docMeta=searcher.doc(doc);
					surl=docMeta.get("url");												
				}
															
				String key=MemcachedTransactions.getUrlKey(surl);					
				row=memcache.getRow(key);
			}
			catch (ConnectException e) { // error communicating with memcached. It will try to reconnect.
				// ignore
			}
			catch (IOException e) { 
				// ignore
				System.err.println("Memcache Exception: "+e.getMessage());
			}				
				
			if (row==null) { // for urls discarded such as dynamics (there are not space to store everything)
				nVersionsURL=1;				
				minTimestampURL=timestamp;
				maxTimestampURL=timestamp;					
			}
			else {
				nVersionsURL=row.getNVersions();				
				minTimestampURL=MemcachedTransactions.intToLongdate(row.getMin());
				maxTimestampURL=MemcachedTransactions.intToLongdate(row.getMax());
			}																
			
			if (functions.hasFunction(funct)) {
				scores.addScore(funct, ((float)minTimestampURL) / PwaIRankingFunction.DAY_MILLISEC); // Oldest version's timestamp in days
			}
			funct++;				
			if (functions.hasFunction(funct)) {						
				scores.addScore(funct, ((float)maxTimestampURL) / PwaIRankingFunction.DAY_MILLISEC ); // Newest version's timestamp in days
			}
			funct++;
			if (functions.hasFunction(funct)) {						
				scores.addScore(funct, ((float)maxTimestampURL-minTimestampURL) / PwaIRankingFunction.DAY_MILLISEC ); // Days between oldest and newest versions						
			}
			funct++;									
			if (functions.hasFunction(funct)) {						
				scores.addScore(funct, (new PwaSpanVersions(maxTimestampURL,minTimestampURL,maxSpan)).score()); // Days between oldest and newest versions normalized
			}			
			funct++;							
			if (functions.hasFunction(funct)) {							
				scores.addScore(funct, nVersionsURL); // NumberVersions
			}
			funct++;					
			if (functions.hasFunction(funct)) {							
				scores.addScore(funct, (new PwaNumberVersions(nVersionsURL,maxVersions)).score()); // NumberVersions normalized
			}
			funct++; 									
			if (functions.hasFunction(funct)) {				
				scores.addScore(funct, (new PwaBoostNewer(timestamp,maxTimestamp,minTimestamp)).score()); // BoostNewer				
			}
			funct++;
			if (functions.hasFunction(funct)) {
				scores.addScore(funct, (new PwaBoostOlder(timestamp,maxTimestamp,minTimestamp)).score()); // BoostOlder
			}
			funct++;
			if (functions.hasFunction(funct)) {
				scores.addScore(funct, (new PwaBoostNewerAndOlder(timestamp,maxTimestamp,minTimestamp)).score()); // BoostNewerAndOlder
			}
			funct++;
						
			//cache.close();
		}
		else {
			funct+=9;
		}			
		
		return scores;
	}
		
	
	/**
	 * Display all features	
	 * @param doc document identifier
	 * @param queryTimestamp timestamp when the query was submitted
	 * @param collector ranking features collector
	 * @param posmanagers query term position into the document 
	 * @param searcher searcher
	 * @param functions ranking functions 
	 * @return explanation
	 */
	public static Explanation explain(int doc, long queryTimestamp, PwaRawFeatureCollector collector, Vector<PwaPositionsManager> posmanagers, Searcher searcher, PwaFunctionsWritable functions) throws IOException {					
		int key;		
		StringBuffer bufValue=new StringBuffer("Feature values of document "+doc+": <span class=\"features\">"); // feature values
		StringBuffer bufBoost=new StringBuffer("Feature boosts of document "+doc+": "); // feature boosts
		StringBuffer bufFinal=new StringBuffer("Feature values*boosts of document "+doc+": "); // feature final scores
		PwaScores scores=score(doc, queryTimestamp, collector, posmanagers, searcher, functions);
		
		Vector<Integer> vecKeys = new Vector<Integer>(functions.keySet());
		Collections.sort(vecKeys);
		for(int i=0;i<vecKeys.size();i++) {			
    		key=vecKeys.get(i);             
    		bufValue.append(" "+key+":"+scores.getScore(key));    
    		bufBoost.append(" "+key+":"+functions.getBoost(key));
    		bufFinal.append(" "+key+":"+scores.getScore(key)*functions.getBoost(key));
        }
		bufValue.append("</span>");
		Explanation allExpl = new Explanation(0,bufValue.toString());		   	
		Explanation expAux = new Explanation(0,bufBoost.toString());
		allExpl.addDetail(expAux);
		expAux = new Explanation(0,bufFinal.toString());
		allExpl.addDetail(expAux);
		return allExpl;			
	}		
	
	/**
	 * Get part of explanation
	 * @param expAux part of explanation
	 * @param functions ranking functions 
	 * @param index index of functions array
	 * @return
	 */
	private static Explanation getExplainPart(Explanation expAux, PwaFunctionsWritable functions, int index) {
		float boost=functions.getBoost(index);
		expAux.addDetail(new Explanation(boost,BOOST_LABEL));
		return expAux;
	}
}
