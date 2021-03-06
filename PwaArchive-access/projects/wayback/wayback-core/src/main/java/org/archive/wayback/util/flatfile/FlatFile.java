/* FlatFile
 *
 * $Id: FlatFile.java 2167 2008-02-01 01:44:53Z bradtofel $
 *
 * Created on 2:09:27 PM Aug 17, 2006.
 *
 * Copyright (C) 2006 Internet Archive.
 *
 * This file is part of Wayback.
 *
 * Wayback is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * any later version.
 *
 * Wayback is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser Public License for more details.
 *
 * You should have received a copy of the GNU Lesser Public License
 * along with Wayback; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */
package org.archive.wayback.util.flatfile;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.io.PrintWriter;
import java.io.RandomAccessFile;
import java.util.Comparator;
import java.util.Iterator;

import org.archive.wayback.util.CloseableIterator;
import org.archive.wayback.util.CompositeSortedIterator;

/**
 * Subclass of File, which allows binary searching, returning Iterators
 * that allow scanning forwards and backwards thru the (sorted) file starting
 * from a particular prefix.
 *
 * @author brad
 * @version $Date: 2008-02-01 01:44:53 +0000 (Fri, 01 Feb 2008) $, $Revision: 2167 $
 */
public class FlatFile {

	private static final long serialVersionUID = 6174187801001601557L;
	private long lastMatchOffset;
	private File file = null;
	/**
	 * 
	 */
	public FlatFile() {
		
	}
	/**
	 * @param parent
	 * @param child
	 */
	public FlatFile(File parent, String child) {
		file = new File(parent,child);
	}
	/**
	 * @param path
	 */
	public FlatFile(String path) {
		file = new File(path);
	}
	
	/**
	 * @param path to set
	 */
	public void setPath(String path) {
		file = new File(path);
	}
	/**
	 * @return current String path, or null if none has been set
	 */
	public String getPath() {
		if(file == null) {
			return null;
		}
		return file.getAbsolutePath();
	}

	/**
	 * Binary search thru RandomAccessFile argument to locate the first line
	 * prefixed by key argument. As a side effect, the RandomAccessFile's
	 * position is also set to the start of the first matching line.  
	 * 
	 * @param fh
	 * @param key
	 * @return long offset where first record prefixed with key is found
	 * @throws IOException
	 */
	public long findKeyOffset(RandomAccessFile fh, String key) throws IOException {
		int blockSize = 8192;
		long fileSize = fh.length();
		long min = 0;
		long max = (long) fileSize / blockSize;
		long mid;
		String line;
	    while (max - min > 1) {
	    	mid = min + (long)((max - min) / 2);
	    	fh.seek(mid * blockSize);
	    	if(mid > 0) line = fh.readLine(); // probably a partial line
	    	line = fh.readLine();
	    	if (key.compareTo(line) > 0) {
	    		min = mid;
	    	} else {
	    		max = mid;
	    	}
	    }
	    // find the right line
	    min = min * blockSize;
	    fh.seek(min);
	    if(min > 0) line = fh.readLine();
	    while(true) {
	    	min = fh.getFilePointer();
	    	line = fh.readLine();
	    	if(line == null) break;
	    	if(line.compareTo(key) >= 0) break;
	    }
	    fh.seek(min);
	    return min;
	}
	/**
	 * @return Returns the lastMatchOffset.
	 */
	public long getLastMatchOffset() {
		return lastMatchOffset;
	}

	/**
	 * @return Iterator returning one String object for each line in the file.
	 * @throws IOException
	 */
	public CloseableIterator<String> getSequentialIterator() throws IOException {
		BufferedReader br = new BufferedReader(new FileReader(file));
		return new RecordIterator(br);
	}
	
	/**
	 * @param prefix
	 * @return Iterator for records beggining with key
	 * @throws IOException
	 */
	public Iterator<String> getRecordIterator(final String prefix) throws IOException {
		RecordIterator itr = null;
		RandomAccessFile raf = new RandomAccessFile(file,"r");
		long offset = findKeyOffset(raf,prefix);
		lastMatchOffset = offset;
		BufferedReader br = new BufferedReader(new FileReader(raf.getFD()));
		itr = new RecordIterator(br);
		return itr;
	}

	/**
	 * 
	 * @param prefix
	 * @return ReverseRecordIterator positioned to return the first line BEFORE
	 *    prefix at the first call to readPrevLine().
	 * @throws IOException
	 */
	public ReverseRecordIterator getReverseRecordIterator(final String prefix) 
		throws IOException {

		ReverseRecordIterator itr = null;
		RandomAccessFile raf = new RandomAccessFile(file,"r");
		long offset = findKeyOffset(raf,prefix);
		if(offset < 1) {
			raf.close();
			return new ReverseRecordIterator(null);
		}
		raf.seek(raf.getFilePointer()-1);
		lastMatchOffset = offset - 1;
		itr = new ReverseRecordIterator(new ReverseBufferedReader(raf));
		return itr;
	}
	
	public void store(Iterator<String> itr) throws IOException {
		PrintWriter pw = new PrintWriter(file);
		while(itr.hasNext()) {
			pw.println(file);
		}
		pw.close();
	}
	
	private static void USAGE() {
		System.err.println("Usage: PREFIX FILE1 [FILE2] ...");
		System.exit(3);
	}
	/**
	 * @param args
	 */
	public static void main(String[] args) {
		
		if(args.length < 2) {
			USAGE();
		}
		String prefix = args[0];
		CloseableIterator<String> itr;
		try {
			if(args.length == 2) {
				FlatFile ff = new FlatFile(args[1]);
				itr = (RecordIterator) ff.getRecordIterator(prefix);
			} else {
				Comparator<String> comp = new Comparator<String>() {
					public int compare(String o1, String o2) {
						return o1.compareTo(o2);
					}
				};
				CompositeSortedIterator<String> csi = 
					new CompositeSortedIterator<String>(comp);
				RecordIterator fitr;
				for(int i=1; i < args.length; i++) {
					FlatFile ff = new FlatFile(args[i]);
					fitr = (RecordIterator) ff.getRecordIterator(prefix);
					csi.addComponent(fitr);
				}
				itr = csi;
			}
			while(itr.hasNext()) {
				String line = (String) itr.next();
				if(!line.startsWith(prefix)) {
					break;
				}
				System.out.println(line);
			}
		} catch (IOException e) {
			e.printStackTrace();
		}
	}
}
