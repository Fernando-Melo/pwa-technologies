<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd" >
<%@page import="java.net.URL"%>
<%@ page
  session="true"
  contentType="text/html; charset=UTF-8"
  pageEncoding="UTF-8"  

  import="java.io.File"
  import="java.io.IOException"
  import="java.net.URLEncoder"
  import="java.text.DateFormat"
  import="java.util.Calendar"
  import="java.util.Date"
  import="java.util.regex.Matcher"
  import="java.util.regex.Pattern"
  import="java.util.GregorianCalendar"
  import="org.apache.hadoop.conf.Configuration"
  import="org.apache.lucene.search.PwaFunctionsWritable"
  import="org.apache.nutch.global.Global"
  import="org.apache.nutch.html.Entities"
  import="org.apache.nutch.metadata.Nutch"
  import="org.apache.nutch.searcher.Hit"
  import="org.apache.nutch.searcher.HitDetails"
  import="org.apache.nutch.searcher.Hits"
  import="org.apache.nutch.searcher.Query"
  import="org.apache.nutch.searcher.Query.Clause"
  import="org.apache.nutch.searcher.NutchBean"
  import="org.apache.nutch.searcher.Summary"
  import="org.apache.nutch.searcher.Summary.Fragment"
  import="org.archive.access.nutch.NutchwaxBean"
  import="org.archive.access.nutch.NutchwaxQuery"
  import="org.archive.access.nutch.NutchwaxConfiguration"
%>
<% // Set the character encoding to use when interpreting request values.
  request.setCharacterEncoding("UTF-8");
%>
<%@ taglib uri="http://java.sun.com/jstl/core" prefix="c" %>
<%@ taglib uri="http://java.sun.com/jstl/fmt_rt" prefix="fmt" %>
<%@ include file="include/logging_params.jsp" %>
<%@ include file="include/i18n.jsp" %>
<fmt:setLocale value="<%=language%>"/>

<%! //To please the compiler since logging need those -- check [search.jsp]
  private static Calendar DATE_START = new GregorianCalendar(1996, 1-1, 1);
  private static final DateFormat FORMAT = new SimpleDateFormat("yyyyMMddHHmmss");
  //TODO: remove dateStart & dateEnd ???
  //private static Calendar dateStart = new GregorianCalendar();
  //private static Calendar dateEnd = new GregorianCalendar();
  private static final DateFormat OFFSET_FORMAT = new SimpleDateFormat("yyyy-MM-dd");
  private static final Pattern OFFSET_PARAMETER = Pattern.compile("(\\d{4})-(\\d{2})-(\\d{2})");

  private static final String COLLECTION_KEY = "collection";
  private static final String COLLECTION_QUERY_PARAM_KEY = COLLECTION_KEY + ":";
  private static final Pattern URL_PATTERN = Pattern.compile("^.*? ?((https?:\\/\\/)?([a-zA-Z\\d][-\\w\\.]+)\\.([a-zA-Z\\.]{2,6})([-\\/\\w\\p{L}\\.~,;:%&=?+$#*]*)*\\/?) ?.*$");
%>
<%-- Get the application beans --%>
<%
  Configuration nutchConf = NutchwaxConfiguration.getConfiguration(application);
  NutchBean bean = NutchwaxBean.get(application, nutchConf);
%>
<%-- Define the default end date --%>
<%
  Calendar DATE_END = new GregorianCalendar();
  DATE_END.set( Calendar.YEAR, DATE_END.get(Calendar.YEAR) );
  DATE_END.set( Calendar.MONTH, 12-1 );
  DATE_END.set( Calendar.DAY_OF_MONTH, 31 );
  DATE_END.set( Calendar.HOUR_OF_DAY, 23 );
  DATE_END.set( Calendar.MINUTE, 59 );
  DATE_END.set( Calendar.SECOND, 59 );
  int queryStringParameter= 0;

  /** Read the embargo offset value from the configuration page. If not present, default to: -1 year */
  try {
        String offsetDateString = getServletContext().getInitParameter("embargo-offset");

        Matcher offsetMatcher = OFFSET_PARAMETER.matcher( offsetDateString );
        offsetMatcher.matches();
        int offsetYear = Integer.parseInt(offsetMatcher.group(1));
        int offsetMonth = Integer.parseInt(offsetMatcher.group(2));
        int offsetDay = Integer.parseInt(offsetMatcher.group(3));

        DATE_END.set(Calendar.YEAR, DATE_END.get(Calendar.YEAR) - offsetYear);
        DATE_END.set(Calendar.MONTH, DATE_END.get(Calendar.MONTH) - offsetMonth);
        DATE_END.set(Calendar.DAY_OF_MONTH, DATE_END.get(Calendar.DAY_OF_MONTH) - offsetDay );
  } catch(IllegalStateException e) {
        // Set the default embargo period to: 1 year
        DATE_END.set( Calendar.YEAR, DATE_END.get(Calendar.YEAR) - 1);
        bean.LOG.error("Embargo offset parameter isn't in a valid format");
  } catch(NullPointerException e) {
        // Set the default embargo period to: 1 year
        DATE_END.set( Calendar.YEAR, DATE_END.get(Calendar.YEAR) - 1);
        bean.LOG.error("Embargo offset parameter isn't present");
  }
%>
<%-- Handle the url parameters --%>
<%
  // get query from request
  
  String queryString = request.getParameter("query");
String[] queryString_splitted=null;

  
  if ( queryString != null ) {
        queryString = queryString.trim();
        
       
  } else {
        // Check if the 'query' params exists
        // else check if the advanced params exist and process them
        queryString = "";
        if ( request.getParameter("adv_and") != null && request.getParameter("adv_and") != "") {
                queryString += request.getParameter("adv_and");
                queryString += " ";
        }
        if ( request.getParameter("adv_phr") != null && request.getParameter("adv_phr") != "") {
                queryString += "\""+ request.getParameter("adv_phr").replaceAll("\"", "") +"\"";
                queryString += " ";
        }
        if ( request.getParameter("adv_not") != null && request.getParameter("adv_not") != "") {
                String notStr = request.getParameter("adv_not");
                if (!notStr.startsWith("-"))
                        notStr = "-" + notStr;
                notStr = notStr.replaceAll("[ -]+", " -") +" ";
                queryString += notStr;
        }
        if ( request.getParameter("adv_mime") != null && request.getParameter("adv_mime") != "" ) {
                queryString += "filetype:"+ request.getParameter("adv_mime");
                queryString += " ";
        }
        if (request.getParameter("site") != null && request.getParameter("site") != "") {
                queryString += "site:";
                String siteParameter = request.getParameter("site");
                if (siteParameter.startsWith("http://")) {
                        queryString += siteParameter.substring("http://".length());
                } else if (siteParameter.startsWith("https://")) {
                        queryString += siteParameter.substring("https://".length());
                } else {
                        queryString += siteParameter;
                }
                /*queryStringParameter = queryString.length();
                if (siteParameter.startsWith("http://") && siteParameter.startsWith("https://")) {
                  queryString +=NutchwaxQuery.encodeExacturl("exacturlexpand:"+siteParameter);
                } else {
                   queryString +=NutchwaxQuery.encodeExacturl("exacturlexpand:http://"+siteParameter);
                       // queryString += "exacturlexpand:http://"+siteParameter;
                }
                String aux = request.getParameter("site");
                bean.LOG.debug("\nQueryString : "+ queryString+"\n*****************************\n");
                String aux_ ="exacturlexpand:http://"+aux;
                aux = NutchwaxQuery.encodeExacturl(aux_);*/
                
                bean.LOG.debug("\nQueryString exactExpand URL: "+ siteParameter+"\n*****************************\n");
                queryString += " ";
        }
        if (request.getParameter("format") != null && request.getParameter("format") != "" && !request.getParameter("format").equals("all")) {
                queryString += "type:" + request.getParameter("format");
                queryString += " ";
        }
  }

  /*****************    'hitsPerDup' param      ***************************/
  int hitsPerDup = 2;
  String hitsPerDupString = request.getParameter("hitsPerDup");
  if (hitsPerDupString != null && hitsPerDupString.length() > 0) {
    hitsPerDup = Integer.parseInt(hitsPerDupString);
  } else {
    // If 'hitsPerSite' present, use that value.
    String hitsPerSiteString = request.getParameter("hitsPerSite");
    if (hitsPerSiteString != null && hitsPerSiteString.length() > 0) {
      hitsPerDup = Integer.parseInt(hitsPerSiteString);
    }
  }

  /*****************    'sort' param    ***************************/
  String sort = null;
  boolean reverse = false;


  if (!queryString.contains("sort:")) {
        sort = request.getParameter("sort");

        if ("relevance".equals(sort)) {
                sort = null;
        } else if ("new".equals(sort)) {
                sort = "date";
                reverse = true;
                queryString += "sort:new";
                hitsPerDup = 0;
        } else if ("old".equals(sort)) {
                sort = "date";
                queryString += "sort:old";
                hitsPerDup = 0;
        } else {
                sort = null;
        }
  } else if (queryString.contains("sort:new")) {
        sort = "date";
        reverse = true;
        hitsPerDup = 0;
  } else if (queryString.contains("sort:old")) {
        sort = "date";
        hitsPerDup = 0;
  }

  // De-Duplicate handling.  Look for duplicates field and for how many
  // duplicates per results to return. Default duplicates field is 'site'
  // and duplicates per results default is '1' (Used to be '2' but now
  // '1' so can have an index with dups not show dups when used doing
  // straight searches).
  String dedupField = request.getParameter("dedupField");
  if (dedupField == null || dedupField.length() == 0) {
    dedupField = "site";
  }

  int hitsPerVersion = 1;
  String hitsPerVersionString = request.getParameter("hitsPerVersion");
  if (hitsPerVersionString != null && hitsPerVersionString.length() > 0) {
        hitsPerVersion = Integer.parseInt(hitsPerVersionString);
  }

  if (queryString.contains("site:")) {
        hitsPerDup = 0;

        queryString = queryString.replaceAll("site:http://", "site:");
        queryString = queryString.replaceAll("site:https://", "site:");
  }

  /***************** Save the query string for further use ***********/
  request.setAttribute("query", queryString.trim());

  /***************** Clean the query for Backend search *************/
  if (queryString.contains("sort:new")) {
        queryString = queryString.replace("sort:new","");
  } else if (queryString.contains("sort:old")) {
        queryString = queryString.replace("sort:old","");
  }

  /*** Start date ***/
  Calendar dateStart = (Calendar)DATE_START.clone();
  SimpleDateFormat inputDateFormatter = new SimpleDateFormat("dd/MM/yyyy");

  if ( request.getParameter("dateStart") != null && !request.getParameter("dateStart").equals("") ) {
        try {
                dateStart.setTime( inputDateFormatter.parse(request.getParameter("dateStart")) );
        } catch (NullPointerException e) {
                bean.LOG.debug("Invalid Start Date:"+ request.getParameter("dateStart") +"|");
        }
  }

  /*** End date ***/
  Calendar dateEnd = (Calendar)DATE_END.clone();                                // Setting current date

  if ( request.getParameter("dateEnd") != null && !request.getParameter("dateEnd").equals("") ) {
        try {
                dateEnd.setTime( inputDateFormatter.parse(request.getParameter("dateEnd")) );
                // be sure to set the end date to the very last second of that day.
                dateEnd.set( Calendar.HOUR_OF_DAY, 23 );
                dateEnd.set( Calendar.MINUTE, 59 );
                dateEnd.set( Calendar.SECOND, 59 );
        } catch (NullPointerException e) {
                bean.LOG.debug("Invalid End Date:"+ request.getParameter("dateEnd") +"|");
        }
  }

  /*** Switch dates if start GT end ***/
    if(dateStart.getTime().compareTo(dateEnd.getTime())>0){
    Calendar auxCal = dateStart;
    dateStart = dateEnd;
    dateEnd = auxCal;
  }
  /**/

// TODO - check if start date is GT end
  /*** Add dates to nutch query ***/
  if (queryString != null && queryString != "") {
        queryString += " date:"+ FORMAT.format( dateStart.getTime() );
        queryString += "-";
        queryString += FORMAT.format( dateEnd.getTime() );
  } else {
        queryString = "";
  }

  String dateStartString = inputDateFormatter.format( dateStart.getTime() );

  String dateEndString = inputDateFormatter.format( dateEnd.getTime() );

  //--- not needed, since we use fields. String htmlQueryString = Entities.encode(queryString);

  /*****************    Offset param    ***************************/
  int start = 0;          // first hit to display
  String startString = request.getParameter("start");
  if (startString != null)
    start = Integer.parseInt(startString);

  /*****************    Hits/page param ***************************/
  int hitsPerPage = 10;          // number of hits to display
  String hitsString = request.getParameter("hitsPerPage");
  if (hitsString != null) {
        try {
                hitsPerPage = Integer.parseInt(hitsString);
        } catch (NumberFormatException e) {
                bean.LOG.debug("WRONG VALUE of hitsPerPage:"+ hitsString +"|");
        }
  }

  // If a 'collection' parameter present, always add to query.
  String collection = request.getParameter(COLLECTION_KEY);
  if (collection != null && queryString != null && queryString.length() > 0) {
      int collectionIndex = queryString.indexOf(COLLECTION_QUERY_PARAM_KEY);
      if (collectionIndex < 0) {
        queryString = queryString + " " + COLLECTION_QUERY_PARAM_KEY +
            collection;
      }
  }
  
  // Prepare the query values to be presented on the page, preserving the session
  String htmlQueryString = "";

  if ( request.getAttribute("query") != null ) {
        htmlQueryString = request.getAttribute("query").toString();
        htmlQueryString = Entities.encode(htmlQueryString);
  }

  // Make up query string for use later drawing the 'rss' logo.
  String params = "&hitsPerPage=" + hitsPerPage +
    (sort == null ? "" : "&sort=" + sort + (reverse? "&reverse=true": "") +
    (dedupField == null ? "" : "&dedupField=" + dedupField));

%>
<%---------------------- Start of HTML ---------------------------%>
<%-- TODO: define XML lang --%>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="pt-PT" lang="pt-PT">
<head>
  <title><fmt:message key='search.meta.title'><fmt:param><c:out value='${requestScope.query}'/></fmt:param></fmt:message></title>
  <meta http-equiv="Content-Type" content="application/xhtml+xml; charset=UTF-8" />
  <%-- TODO: define META lang --%>
  <meta http-equiv="Content-Language" content="pt-PT" />
  <meta name="Keywords" content="<fmt:message key='search.meta.keywords'/>" />
  <meta name="Description" content="<fmt:message key='search.meta.description'/>" />
  <link rel="shortcut icon" href="img/logo-16.jpg" type="image/x-icon" />
  <link rel="search" type="application/opensearchdescription+xml" title="<fmt:message key='opensearch.title'><fmt:param value='<%=language%>'/></fmt:message>" href="opensearch.jsp?l=<%=language%>" />
  <link rel="stylesheet" title="Estilo principal" type="text/css" href="css/style.css"  media="all" />
  <link rel="stylesheet" type="text/css" href="css/jquery-ui-1.7.2.custom.css" />
  <script type="text/javascript">
                var minDate = new Date(<%=DATE_START.getTimeInMillis()%>);
                var maxDate = new Date(<%=DATE_END.getTimeInMillis()%>);
        </script>
        <script type="text/javascript" src="js/jquery-1.3.2.min.js"></script>
        <script type="text/javascript" src="js/jquery-ui-1.7.2.custom.min.js"></script>
        <script type="text/javascript" src="js/ui.datepicker.js"></script>
        <% if (language.equals("pt")) { /* load PT i18n for datepicker */ %>
        <script type="text/javascript" src="js/ui.datepicker-pt-BR.js"></script>
        <% } %>
        <script type="text/javascript" src="js/configs.js"></script>
</head>
<body>
  <%@ include file="include/topbar.jsp" %>
<%-- TODO: add loading feedback --%>
  <div class="wrap" id="firstWrap">
    <div id="main">
      <div id="header">
        <%@ include file="include/logo.jsp" %>
        <div id="search-header">
            <form id="loginForm" action="search.jsp" name="loginForm" method="get">
              <input type="hidden" name="l" value="<%= language %>" />
              <fieldset id="pesquisar">
                <label for="txtSearch">&nbsp;</label>
                <input class="search-inputtext" type="text" size="15"  value="<%=htmlQueryString%>" onfocus="if(this.value=='<fmt:message key='search.value'/>') this.value=''; " onblur=" if(this.value=='')this.value='<fmt:message key='search.value'/>' " name="query" id="txtSearch" accesskey="t" />
                <input type="reset" src="img/search-resetbutton.html" value="" alt="reset" class="search-resetbutton" name="btnReset" id="btnReset" accesskey="r" />
                <input type="submit" value="<fmt:message key='search.submit'/>" alt="<fmt:message key='search.submit'/>" class="search-submit" name="btnSubmit" id="btnSubmit" accesskey="e" />
                <%
                  StringBuilder advUrl = new StringBuilder();
                  advUrl.append("advanced.jsp?");

                  if (htmlQueryString != null && !htmlQueryString.equals("")) {
                    advUrl.append("query=");
                    advUrl.append( URLEncoder.encode(htmlQueryString, "UTF-8") );
                  }

                  advUrl.append("&dateStart=");
                  advUrl.append(dateStartString);
                  advUrl.append("&dateEnd=");
                  advUrl.append(dateEndString);

                  advUrl.append("&hitsPerPage=");
                  advUrl.append(hitsPerPage);

                  advUrl.append("&l=");
                  advUrl.append(language);

                  if (sort != null) {
                    advUrl.append("&sort=");
                    advUrl.append(sort);
                    if (reverse) {
                      advUrl.append("&reverse=");
                      advUrl.append(reverse);
                    }
                  }
                %>
                <a href="<%=advUrl.toString()%>" title="<fmt:message key='search.advanced'/>" id="pesquisa-avancada"><fmt:message key='search.advanced'/></a>
              </fieldset>
              <fieldset id="search-date">
                <div id="search-label-data">
                  <label id="search-dateStart_top" for="dateStart_top"><fmt:message key='search.query-form.from'/></label>
                  <div class="search-withTip">
                    <input type="text" id="dateStart_top" name="dateStart" value="<%=dateStartString%>" />
                  </div>
                  <label id="search-labelDateEnd" for="dateEnd_top"><fmt:message key='search.query-form.to'/></label>
                  <div class="withTip">
                    <input type="text" id="dateEnd_top" name="dateEnd" value="<%=dateEndString%>" />
                  </div>
                </div>
              </fieldset>
            </form>
        </div>
      </div>
<%-- END OF HEADER --%>
  
        <%----------------------------------------------------------
        // Check to see which of the 3 mode is presented:
        // (1) result list
        // (2) wayback document's grid
        // (3) result list with tip
        ----------------------------------------------------------%>
        <%
        Matcher urlMatch = null;
        String urlQuery = null;
        boolean showList = false;
        String showTip = null;                  // tip to show
        String allVersions = null;
        int end = -1;
        Hits hits = null;
        int hitsLength = 0;
        long hitsTotal = 0;
        boolean hitsTotalIsExact = false;
        Query query = null;
        String queryExactExpand=null;
        String collectionsHost = nutchConf.get("wax.host", "examples.com");
        pageContext.setAttribute("collectionsHost", collectionsHost);

              String hostArquivo = nutchConf.get("wax.webhost", "arquivo.pt");


        if ( request.getAttribute("query") != null && !request.getAttribute("query").toString().equals("") ) {

                if ( (urlMatch = URL_PATTERN.matcher( request.getAttribute("query").toString() )).matches() ) {
                        urlQuery = urlMatch.group(1);
                        String urlQueryParam = urlQuery;
                        int urlLength = urlQuery.length();
          
                        if (!urlQuery.startsWith("http://") && !urlQuery.startsWith("https://") ) {
                                urlQueryParam = "http://" + urlQueryParam;
                        }
                pageContext.setAttribute("urlQueryParam", urlQueryParam);

                        allVersions = "search.jsp?query="+ URLEncoder.encode(urlQueryParam, "UTF-8");
                        if (!language.equals("pt")) {
                                allVersions += "&l="+ language;
                        }

            if ( request.getParameter("query") != null && urlLength == request.getParameter("query").trim().length() ) {
                                // option: (2)
                                showList = false;
                                usedWayback = true;
                                
                                /*
                            hostname is not case sensitive, thereby it has to be written with lower case
                            the bellow provide a solution to this problem
                            arquivo.PT will be equal to arquivo.pt
                            Converts hostname to small letters
                            */
                            URL url_queryString=new URL(urlQueryParam);
                            String path=url_queryString.getPath();
                            String hostname=url_queryString.getHost().toLowerCase();
                            String protocol=url_queryString.getProtocol();
                            urlQueryParam= protocol+"://"+hostname+path;
                            
                          /*************************************/
                            queryString=urlQueryParam;
                        
                            /*************************************************/
                    pageContext.setAttribute("urlQueryParam", urlQueryParam);
                    allVersions = "search.jsp?query="+ URLEncoder.encode(urlQueryParam, "UTF-8");
              pageContext.setAttribute("dateStartWayback", FORMAT.format( dateStart.getTime() ) );
                        pageContext.setAttribute("dateEndWayback", FORMAT.format( dateEnd.getTime() ) );

                        long startQueryTime = System.currentTimeMillis();               // for logging
%>

      </div> <%-- closes #main --%>
      </div> <%-- closes .wrap --%>
      
                        <%-- #search_stats & #result_list for this case are generated by WB --%>
                        <%
                                boolean seeHistory = false;             // This variable is used to indicate that link to see the history was clicked
                                if( request.getParameter("pos") != null) {
                                        seeHistory = true;
                                }
                                pageContext.setAttribute("seeHistory", seeHistory);
                        %>
                        <c:catch var="exception">
                                <% hitsTotal = 1; %>
                        </c:catch>


    <script src="http://<%=hostArquivo%>/js/jquery-latest.min.js" type="text/javascript"></script>
    <script>var $j = jQuery.noConflict(true);</script>


<script type="text/javascript">

Content = {
    months: 
    {  '01': "<fmt:message key="month.0" />",
       '02': "<fmt:message key="month.1" />",
       '03': "<fmt:message key="month.2" />",
       '04': "<fmt:message key="month.3" />",
       '05': "<fmt:message key="month.4" />",
       '06': "<fmt:message key="month.5" />",
       '07': "<fmt:message key="month.6" />",
       '08': "<fmt:message key="month.7" />",
       '09': "<fmt:message key="month.8" />",
       '10': "<fmt:message key="month.9" />",
       '11': "<fmt:message key="month.10" />",
       '12': "<fmt:message key="month.11" />",
    },
    shortMonths: 
    {  '01': "<fmt:message key="smonth.0" />",
       '02': "<fmt:message key="smonth.1" />",
       '03': "<fmt:message key="smonth.2" />",
       '04': "<fmt:message key="smonth.3" />",
       '05': "<fmt:message key="smonth.4" />",
       '06': "<fmt:message key="smonth.5" />",
       '07': "<fmt:message key="smonth.6" />",
       '08': "<fmt:message key="smonth.7" />",
       '09': "<fmt:message key="smonth.8" />",
       '10': "<fmt:message key="smonth.9" />",
       '11': "<fmt:message key="smonth.10" />",
       '12': "<fmt:message key="smonth.11" />",
    },
    savedInArchive:"<fmt:message key="savedInArchive" />",
    versionsStored:"<fmt:message key="versionsStored" />",
    versionsPage:"<fmt:message key="versionsPage" />",
    between:"<fmt:message key="between" />",
    and:"<fmt:message key="and" />",
    resultsQuestion:"<fmt:message key="resultsQuestion" />",
    moreOptions:"<fmt:message key="moreOptions" />",
    lessOptions:"<fmt:message key="lessOptions" />",
    help:"<fmt:message key="help" />",
    helpHref:"<fmt:message key="helpHref" />",
    newSearch:"<fmt:message key="newSearch" />",
    at:"<fmt:message key="at" />",
    shareMessage:"<fmt:message key="shareMessage" />",
    language:"<fmt:message key="language" />",
    otherDates:"<fmt:message key="otherDates" />",
    emailMessage:"<fmt:message key="emailMessage" />",
    noResultsFound:"<fmt:message key="noResultsFound" />",
    suggestions:"<fmt:message key="suggestions" />",
    checkSpelling:"<fmt:message key="checkSpelling" />",
    differentKeywords:"<fmt:message key="differentKeywords" />",
    generalWords:"<fmt:message key="generalWords" />", 
    internetArchive:"<fmt:message key="internetArchive" />",
    suggestSiteArchived:"<fmt:message key="suggestSiteArchived" />",
    suggestUrl:"<fmt:message key="suggestUrl" />",
    suggest:"<fmt:message key="suggest" />", 
    mementoFind:"<fmt:message key="mementoFind" />",
    embargo:"<fmt:message key="embargo" />",
    embargoUrl:"<fmt:message key="embargoUrl" />",
    notArchived:"<fmt:message key="notArchived" />",
    otherLanguage: "<fmt:message key="otherLanguage" />"  ,
    preservedByArquivo: "<fmt:message key="preservedByArquivo" />"     
};


function getYearTs(ts){
  return ts.substring(0, 4);
}

function getYearPosition(ts){
  return parseInt(getYearTs(ts)) - 1996;
}

function getDateSpaceFormated(ts){
  var year = ts.substring(0, 4);
  var month = ts.substring(4, 6);
  month = Content.months[month];
  var day = ts.substring(6, 8);
  return day + " "+ month + " " +year;

}

function getShortDateSpaceFormated(ts){
  var year = ts.substring(0, 4);
  var month = ts.substring(4, 6);
  month = Content.shortMonths[month];
  var day = ts.substring(6, 8);
  return day + " "+ month;

}

function createMatrix(versionsArray, versionsURL){
  var today = new Date();
  numberofVersions = yyyy - 1996;
  var yyyy = today.getFullYear();
  var numberofVersions = yyyy - 1996;
  var matrix = new Array(numberofVersions);
  for (var i = 0; i < matrix.length; i++) {
    matrix[i] = [];
    var yearStr = (1996+i).toString();
    // add the headers for each year
    $("#years").append('<th id="th_'+yearStr+'">'+yearStr+'</th>');
  }

  for (var i = 0; i < versionsArray.length; i++) {
    var timestamp = versionsArray[i];
    var timestampStr = timestamp.toString();
    var url = versionsURL[i];
    var pos = getYearPosition(timestampStr);
    var dateFormated = getDateSpaceFormated(timestampStr);
    var shortDateFormated= getShortDateSpaceFormated(timestampStr);       
    var tdtoInsert = '<td><a href="http://<%=collectionsHost%>/'+timestampStr+'/'+url+'" title="'+dateFormated+'">'+shortDateFormated+'</a></td>';
    matrix[pos].push(tdtoInsert);  
  }

  //find which is the biggest number of versions per year and create empty tds in the other years
  var maxLength = 0;
  var lengthi =0;
  for (var i = 0; i < matrix.length; i++) {
    lengthi = matrix[i].length;
    var yearStr = (1996+i).toString();
    if(lengthi == 0){
      $("#th_"+yearStr).addClass("inactivo");
    }

    if(lengthi > maxLength){
      maxLength = lengthi;
    }
  }
  //iterate again to create empty tds
  for (var i = 0; i < matrix.length; i++) {
    lengthi = matrix[i].length;
    if(maxLength > lengthi){
      for(var j=0; j<(maxLength - lengthi); j++){
        matrix[i].push('<td>&nbsp;</td>');
      }
    }
  }
  //create each row of the table
  for (var i=0; i<maxLength; i++){
    rowString ="";
    for (var j = 0; j < matrix.length; j++) {
      rowString+= matrix[j][i];
    }
    var rowId = (i+1).toString()
    $("#tableBody").append('<tr id="'+rowId+'">'+rowString+'<tr>');
  }
  $('#1 td:nth-child('+String(matrix.length)+')').html('<a href="'+Content.embargoUrl+'">'+Content.embargo+'</a>');
}


function createResultsPage(numberOfVersions, inputURL){
    
    $('<div class="clear">&nbsp;</div>'+
      '<div id="resultados-url">'+Content.resultsQuestion+' <a href="search.jsp?query=%22'+inputURL+'%22">'+inputURL+'</a>?</div>'+
      '<div class="wrap">' +
             '  <div id="intro">' +
             '    <h1 style="text-align: center;">'+Content.versionsStored+'</h1>' +
             '    <span class="texto-1" style="text-align: center;">'+ numberOfVersions +' ' + Content.versionsPage+' '+ inputURL+
                '</span>' +
             '  </div>' +
             '</div>' + 
       '<div id="conteudo-versoes">'+
             '  <div id="resultados-lista">'+
             '    <table class="tabela-principal">'+
             '      <thead>'+
             '        <tr id="years">'+
             '        </tr>'+
             '      </thead>'+
             '      <tbody id="tableBody">'+
             '      </tbody>'+
             '    </table>'+
             '  </div>'+
             '</div>'        ).insertAfter("#firstWrap");
     
}
function createErrorPage(){
  $('<div id="conteudo-resultado">'+
           '  <div id="first-column">&nbsp;</div>'+
           '  <div id="second-column">'+
           '    <div id="search_stats"></div>'+
           '    <div id="conteudo-pesquisa-erro">'+
                '<h2>'+Content.noResultsFound+' </h2> <h3><%=urlQuery%></h3>'+
                '<div id="sugerimos-que">'+
                    '<p>'+Content.suggestions+'</p>'+
                  '<ul>'+
                    '<li>'+Content.checkSpelling+'</li>'+
                    '<li><a style="padding-left: 0px;" href="'+Content.suggestUrl+'<%=urlQuery%>">'+Content.suggest+'</a> '+Content.suggestSiteArchived+'</li>'+                    
                    '<li>'+Content.internetArchive+'<a href="http://wayback.archive.org/web/*/<%=urlQuery%>">Internet Archive</a>.</li>'+
                    '<li><a href="http://timetravel.mementoweb.org/list/1996/<%=urlQuery%>" style="padding-left: 0px;">'+Content.mementoFind+'</a>.</li>'+                    
                  '</ul>'+
                '</div>'+
                '</div>'+
              '</div>'+
           '</div>').insertAfter("#firstWrap"); 
}


    //top.alert("Starting the Code!")
    var urlsource = "<%=urlQuery%>" ;
    //var requestURL = "http://p27.arquivo.pt/wayback/-cdx";
    var requestURL = "http://<%=collectionsHost%>/" + "-cdx";
    var versionsArray = [];
    var versionsURL = [];

    var inputURL = document.getElementById('txtSearch').value;


    $.ajax({
    // example request to the cdx-server api - 'http://arquivo.pt/pywb/replay-cdx?url=http://www.sapo.pt/index.html&output=json&fl=url,timestamp'
       url: requestURL,
       data: {
          output: 'json',
          url: urlsource,
          fl: 'url,timestamp'
       },
       error: function() {
         // Apresenta que não tem resultados!
         createErrorPage();
       },
       dataType: 'text',
       success: function(data) {

        //top.alert("I received the versions");
          versionsArray = []
          var tokens = data.split('\n')
          $.each(tokens, function(e){
              if(this != ""){
                  var version = JSON.parse(this);
                  versionsArray.push(version.timestamp);
                  versionsURL.push(version.url);
                   
              }
              
          }); 
          createResultsPage(tokens.length - 1, inputURL);
          createMatrix(versionsArray, versionsURL);
          //top.alert(versionsArray.length)
       },
       async: false,
       type: 'GET'
    });
</script>


<script>
      var language = Cookies.get('language');
      if( language == 'EN'){
          document.write('<script type="text/javascript" language="JavaScript" src="http://<%=hostArquivo%>/js/properties/ConstantsEN.js"><\/script>');
      }
      else{
          document.write('<script type="text/javascript" language="JavaScript" src="http://<%=hostArquivo%>/js/properties/ConstantsPT.js"><\/script>');
      }
</script> 




                        <c:if test="${not empty exception}">
        <% bean.LOG.error("Error while accessing to wayback: "+ pageContext.getAttribute("exception")); %>
        <div id="conteudo-resultado"> <%-- START OF: conteudo-resultado --%>
        <div id="first-column">
                &nbsp;
        </div>
        <div id="second-column">
          <div id="search_stats"></div>
                        </c:if>

                        <% queryTime = (int) (System.currentTimeMillis() - startQueryTime); //for logging %>
        



<%

            } else {
              // option: (3)
                                showList = true;                    
                                showTip = urlMatch.group(1);
                                if (queryString.contains("site:")){ // It expands an URL since it is an advanced search
                                  queryString_splitted = queryString.split(" ");
                                  String queryString_expanded="";
                                  for (int i =0; i<queryString_splitted.length;i++){
                                   if (queryString_splitted[i].contains("site:")){
                                    queryString_splitted[i]= NutchwaxQuery.encodeExacturl("exacturlexpand:http://"+queryString_splitted[i].replace("site:", ""));
                                   }
                                  queryString_expanded+=" "+queryString_splitted[i];
                                  }
                          
                                        query = NutchwaxQuery.parse(queryString_expanded, nutchConf);    //create the query object
                                }
                                else
                                  query = NutchwaxQuery.parse(queryString, nutchConf);    //create the query object
                                bean.LOG.debug("query: " + query.toString());
            }
          } else {
            // option: (1)
                        query = NutchwaxQuery.parse(queryString, nutchConf);            //create the query object
                        bean.LOG.debug("query: " + query.toString());
            
            showList = true;
          }
        }
        %>
          
      
<% if (showList) { %>

<div id="conteudo-resultado"> <%-- START OF: conteudo-resultado --%>
<div id="first-column">
  &nbsp;
</div>
<div id="second-column">
<h1><fmt:message key='search.query'><fmt:param><c:out value='${requestScope.query}'/></fmt:param></fmt:message></h1>

<%@include file="include/search-result-component.jsp"%>

<% } %> <%-- END OF: showList --%>

  <% 
        if (hitsLength >= end || hitsLength > start) {
                long pagesAvailable = (long) (hitsTotal / hitsPerPage) ;
                        if ((hitsTotal % hitsPerPage) != 0) {
                                pagesAvailable++;
                        }

                        // Check if we are in the last page
                        if (hitsLength == end && hitsPerDup != 0) {
                                pagesAvailable = (long) (hitsLength / hitsPerPage);
                                if ((hitsLength % hitsPerPage) != 0) {
                                        pagesAvailable++;
                                }
                        }
        
            long currentPage = (long) ((start + 1) / hitsPerPage + 1) ;
            int maxPagesToShow = 10;
            long displayMin = (long) (currentPage - (0.5 * maxPagesToShow) );
        
            if (displayMin < 1) {
              displayMin = 1; 
            }
        
            long displayMax = displayMin + maxPagesToShow - 1 ;
            if (displayMax > pagesAvailable) {
              displayMax = pagesAvailable;
            }
        %>

<%-- ---------------- --%>
<%-- No results presentend --%>
<%-- ---------------- --%>

<% if ( hitsTotal == 0) { %>

<%
        // When empty query → intro page
        if ( request.getAttribute("query").equals("") ) {
%>
        <div id="search_stats"></div>
        <div id="no_results">
    <c:redirect url='index.jsp'>
      <c:param name='l' value='${language}'/>
    </c:redirect>
  </div>
        <% } else { %>
  <div id="conteudo-pesquisa-erro">
    <h2><fmt:message key='search.no-results.title'/></h2>
    <h3><%=htmlQueryString%></h3>

    <div id="sugerimos-que">
        <p><fmt:message key='search.no-results.suggestions'/></p>
      <ul>
        <li><fmt:message key='search.no-results.suggestions.well-written'/></li>
        <li><fmt:message key='search.no-results.suggestions.time-interval'/></li>
        <li><fmt:message key='search.no-results.suggestions.keywords'/></li>
        <li><fmt:message key='search.no-results.suggestions.generic-words'/></li>
        <%-- Show specific suggestions for URL queries --%>
        <% if ( usedWayback) { %>
        <li><fmt:message key='search.no-results.suggestions.internet-archive'><fmt:param value='<%=urlQuery%>'/></fmt:message></li>
        <li><fmt:message key='search.no-results.suggestions.suggest'><fmt:param value='<%=urlQuery%>'/></fmt:message></li>
        <% } %>
      </ul>
    </div>
    <div class="voltar-erro"><a href="<%= request.getHeader("Referer")%>">&larr; <fmt:message key='search.no-results.go-back'/></a></div>
  </div>

<%
        }

   } else if (showList && hitsTotal != 0 && hitsPerDup != 0 && currentPage >= pagesAvailable && hitsTotal > end) {
   long previousPageStartForDup = (currentPage - 2) * hitsPerPage;
    String previousPageUrlForDup = request.getContextPath() + "search.jsp?" +
      "query=" + htmlQueryString +
      "&dateStart="+ dateStartString +
      "&dateEnd="+ dateEndString +
      "&start=" + previousPageStartForDup +
      "&hitsPerPage=" + hitsPerPage +
      "&hitsPerDup=" + 0 +
      "&dedupField=" + dedupField;
    if (sort != null) {
      previousPageUrlForDup = previousPageUrlForDup +
      "&sort=" + sort +
      "&reverse=" + reverse;
    }
  
  String noDupQuery = request.getContextPath() + "/search.jsp?" +
      "query=" + htmlQueryString +
      "&dateStart="+ dateStartString +
      "&dateEnd="+ dateEndString +
      "&start=" + 0 +
      "&hitsPerPage=" + hitsPerPage +
      "&hitsPerDup=" + 0 +
      "&dedupField=" + dedupField +
      "&l="+ language;
      if (sort != null) {
        previousPageUrlForDup = previousPageUrlForDup +
        "&sort=" + sort +
        "&reverse=" + reverse;
      }

         %>
  <div class="omitted-results">
    <fmt:message key="search.results.omitted"><fmt:param value="<%=noDupQuery%>"/></fmt:message>.
  </div>
<% } %>


<% if (hitsTotal >= 1 && !usedWayback) { %>              <%-- Start Pager IF --%>
<div class="pagination">

<ul>
<%
if (currentPage > 1) {
long previousPageStart = (currentPage - 2) * hitsPerPage;
    String previousPageUrl = "search.jsp?" +
      "query=" + URLEncoder.encode(request.getAttribute("query").toString(), "UTF-8") +
      "&dateStart="+ dateStartString +
      "&dateEnd="+ dateEndString +
      "&pag=prev" +                             // mark as 'previous page' link 
      "&start=" + previousPageStart +
      "&hitsPerPage=" + hitsPerPage +
      "&hitsPerDup=" + hitsPerDup +
      "&dedupField=" + dedupField +
      "&l="+ language;
    if (sort != null) {
      previousPageUrl = previousPageUrl +
      "&sort=" + sort +
      "&reverse=" + reverse;
    }
%>
  <li class="previous"><a href="<%=previousPageUrl%>" title="<fmt:message key='search.pager.previous'/>"><fmt:message key='search.pager.previous'/></a></li>
<% } %>
<%
  for (long pageIndex = displayMin; pageIndex <= displayMax; pageIndex++) {
    long pageStart = (pageIndex - 1) * hitsPerPage;
    String pageUrl = "search.jsp?" +
      "query=" + URLEncoder.encode(request.getAttribute("query").toString(), "UTF-8") +
      "&dateStart="+ dateStartString +
      "&dateEnd="+ dateEndString +
      "&pag=" + pageIndex +
      "&start=" + pageStart +
      "&hitsPerPage=" + hitsPerPage +
      "&hitsPerDup=" + hitsPerDup +
      "&dedupField=" + dedupField +
      "&l="+ language;
    if (sort != null) {
      pageUrl = pageUrl +
      "&sort=" + sort +
      "&reverse=" + reverse;
    }
    if (pageIndex != currentPage) {
%>
    <li><a href="<%=pageUrl%>"><%=pageIndex%></a></li>
<%
    }
        else {
%>
    <li class="current"><%=pageIndex%></li>
<%
    }
  }

  if (currentPage < pagesAvailable) {
    long nextPageStart = currentPage * hitsPerPage;
    String nextPageUrl = "search.jsp?" +
      "query=" + URLEncoder.encode(request.getAttribute("query").toString(), "UTF-8") +
      "&dateStart="+ dateStartString +
      "&dateEnd="+ dateEndString +
      "&pag=next" +
      "&start=" + nextPageStart +
      "&hitsPerPage=" + hitsPerPage +
      "&hitsPerDup=" + hitsPerDup +
      "&dedupField=" + dedupField +
      "&l="+ language;
    if (sort != null) {
      nextPageUrl = nextPageUrl +
      "&sort=" + sort +
      "&reverse=" + reverse;
    }
%>
    <li class="next"><a href="<%=nextPageUrl%>" title="<fmt:message key='search.pager.next'/>"><fmt:message key='search.pager.next'/></a></li>
<% } %>

</ul>

</div>
<% } %>                 <%-- End of pager IF --%>
<% } %>
</div>

      </div>  <!-- FIM #conteudo-resultado  --> 
    </div>
  </div>
<%@include file="include/footer.jsp" %>
<%@include file="include/analytics.jsp" %>
</body>
</html>

<%@include file="include/logging.jsp" %>