from typing import Union,Dict
from fastapi import FastAPI, Request,HTTPException
from charset_normalizer import detect
import logging
import json
from requests import get
from io import BytesIO
import os
import asyncio

#verex ai
import vertexai
from vertexai.language_models import TextEmbeddingInput, TextEmbeddingModel
from vertexai.generative_models import GenerationConfig, GenerativeModel
from tenacity import retry, wait_random_exponential
import vertexai.generative_models as generative_models

#firebase
import firebase_admin
from firebase_admin import firestore
from google.cloud.firestore_v1.base_vector_query import DistanceMeasure
from google.cloud.firestore_v1.vector import Vector

#markdown
import re
import urllib.request as req
from bs4 import BeautifulSoup
from urllib.parse import urljoin
import mistune
from mistune.renderers.markdown import MarkdownRenderer
from mistune.core import BlockState
from markitdown import MarkItDown
import pymupdf4llm
from pdfminer.pdfparser import PDFSyntaxError
#cloudrun
from cloudevents.http import from_http
from google.events.cloud import firestore as google_firestore_event
from google.protobuf.json_format import MessageToDict

logging.basicConfig(
    level=logging.DEBUG, 
    format="%(asctime)s - %(levelname)s - %(message)s"  
)

LANGUAGE = "Japanese"
NUM = 300
LIMITPERDOC = 7000
MINLEN = 25 #処理する最小文字数

# Firebase を初期化（GCP専用)
firebase_admin.initialize_app()

# Firestoreクライアントを作成
db = firestore.client()
#vertexaiを初期化
vertexai.init()


safety_settings = {
    generative_models.HarmCategory.HARM_CATEGORY_HATE_SPEECH: generative_models.HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
    generative_models.HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT: generative_models.HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
    generative_models.HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT: generative_models.HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
    generative_models.HarmCategory.HARM_CATEGORY_HARASSMENT: generative_models.HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
}

app = FastAPI()
@app.post("/deleteSummary")
async def deleteSum(request:Request):
    try:
        logging.info(f"✅deleteDoc started")
        body = await request.body()
        event = from_http(request.headers, body)
        encoded_data = event.data
        logging.info(f"✅got data encoded{encoded_data}")
        firestore_payload = google_firestore_event.DocumentEventData()
        firestore_payload._pb.ParseFromString(encoded_data)
        old_value_dict = MessageToDict(firestore_payload.old_value._pb) if firestore_payload.old_value else {}
        logging.info(f"✅got data decoded{old_value_dict}")
        old_value_dict = old_value_dict.get("fields", {})
        knowledgeIds = list(old_value_dict["knowledges"].values())[0]
        knowledgeIds = extract_ids(knowledgeIds)
        sumId = list(old_value_dict["id"].values())[0]
        deleteKnowledges(knowledgeIds)
        logging.info(f"🍺Done: {sumId}")
    except Exception as e:
        logging.error(f"Error processing Firestore event: {e}")

         
    
@app.post("/deleteDoc")
async def deleteDoc(request:Request):
    try:
        logging.info(f"✅deleteDoc started")
        body = await request.body()
        event = from_http(request.headers, body)
        encoded_data = event.data
        logging.info(f"✅got data encoded{encoded_data}")
        firestore_payload = google_firestore_event.DocumentEventData()
        firestore_payload._pb.ParseFromString(encoded_data)
        old_value_dict = MessageToDict(firestore_payload.old_value._pb) if firestore_payload.old_value else {}
        #new_value_dict = MessageToDict(firestore_payload.value._pb) if firestore_payload.value else {}
        logging.info(f"✅got data decoded{old_value_dict}")
        old_value_dict = old_value_dict.get("fields", {})
        contentIds = list(old_value_dict["contents"].values())[0]
        contentIds = extract_ids(contentIds)
        docId = list(old_value_dict["id"].values())[0]
        deleteContents(contentIds)
        logging.info(f"🍺Done: {docId}")
    except Exception as e:
        logging.error(f"Error processing Firestore event: {e}")


@app.post("/initDoc")
async def initializeDoc(request:Request):
    try:
        logging.info(f"✅initDoc started")
        body = await request.body()
        event = from_http(request.headers, body)
        document = event.get("document")
        inputId = document.split("/")[-1]
        logging.info(f"✅got inputId: {inputId}")
        encoded_data = event.data
        logging.info(f"✅got data encoded{encoded_data}")
        firestore_payload = google_firestore_event.DocumentEventData()
        firestore_payload._pb.ParseFromString(encoded_data)
        new_value_dict = MessageToDict(firestore_payload.value._pb) if firestore_payload.value else {}
        logging.info(f"✅got data decoded{new_value_dict}")
        new_value_dict = new_value_dict.get("fields", {})
        userId = list(new_value_dict["userId"].values())[0]
        inputType = list(new_value_dict["type"].values())[0]
        inputDetail = list(new_value_dict["detail"].values())[0]
        if 'title' in new_value_dict:
            title = list(new_value_dict["title"].values())[0]
        else:
            title = "無題のタイトル"
        docTitle = get_title({'type':inputType,'detail':inputDetail},title)

        input = {'userId':userId,'doc':{'type':inputType,'detail':inputDetail},'title':docTitle}
        docId =  await initDoc(input,num=NUM,limitPerDoc=LIMITPERDOC)
        update_input_to_firestore(inputId,{"docId":docId})
        logging.info(f"🍺Done: {inputId}")
    except Exception as e:
        logging.error(f"Error processing Firestore event: {e}")
 
@app.post("/doSearch")
async def doVectorSearch(request:Request):
    try:
        #リクエストボディの整形
        logging.info("✅start doSearch")
        body = await request.body()
        event = from_http(request.headers, body)
        document = event.get("document")
        logging.info(f"✅document{document} from doSearch")
        contentId = document.split("/")[-1] #リクエストボディからidを取得
        logging.info(f"✅contentId :{contentId}from doSearch")
        encoded_data = event.data
        firestore_payload = google_firestore_event.DocumentEventData()
        firestore_payload._pb.ParseFromString(encoded_data)
        new_value_dict = MessageToDict(firestore_payload.value._pb) if firestore_payload.value else {}
        new_value_dict = new_value_dict.get("fields", {})
        logging.info(f"✅got data decoded{new_value_dict}  from doSearch")
        userId = list(new_value_dict["userId"].values())[0]
        contentState = list(new_value_dict["state"].values())[0]
        contentDetail = list(new_value_dict["detail"].values())[0]
        contentDocId = list(new_value_dict["docId"].values())[0]
        vector_data = new_value_dict["vector"]
        vector = [item['doubleValue'] for item in vector_data['arrayValue']['values']]

        logging.info(f"✅vector size:{len(vector)}")
        if contentState == "ready":
            return None
        contentContext = list(new_value_dict["context"].values())[0]
        logging.info(f"✅vector search started!! contentId:{contentId}")
        result = await doSearch(userId,contentId,contentDetail,contentDocId,vector,num=NUM,threshold=0.35)
        logging.info(f"✅vector search finished!! contentId:{contentId}")
        return result
    except Exception as e:
        update_content_to_firestore(contentId,{"state":"ready"})

        


@app.post("/makeProf")
async def makeProf(request:Request):
    try:
        #リクエストボディの整形
        logging.info("✅start doSearch")
        body = await request.body()
        event = from_http(request.headers, body)
        document = event.get("document")
        logging.info(f"✅document{document} from doSearch")
        userId = document.split("/")[-1] #リクエストボディからidを取得
        logging.info(f"✅usersId :{userId}from doSearch")
        encoded_data = event.data
        firestore_payload = google_firestore_event.DocumentEventData()
        firestore_payload._pb.ParseFromString(encoded_data)
        new_value_dict = MessageToDict(firestore_payload.value._pb) if firestore_payload.value else {}
        new_value_dict = new_value_dict.get("fields", {})
        logging.info(f"✅got data decoded{new_value_dict}  from doSearch")
        preference = list(new_value_dict["preference"].values())[0]
        language = list(new_value_dict["language"].values())[0]
        prof,language = await makeProf(preference,language)
        create_profiles_to_firestore(userId,prof,language)
        logging.info(f"✅profile added userId:{userId},profile:{prof}")
    except Exception as e:
        logging.error(f"Error processing Firestore event: {e}")

#manage
async def initDoc(input,num = 200,limitPerDoc = 7000):
    """
    Args: arg: {'userId' (String)
                    'doc'  {'type':String, 'detail': String },
                    'title' (String)
                    },
    (e.g. )
        { 'userId':"cyC421CyMJlC7B2",'doc':{'type':'url','detail':"https://zenn.dev/hackathons/2024-google-cloud-japan-ai-hackathon", 'title':"Google Cloud Japan AI Hackathon"}},
    save_knowledge (bool) : whether save knowledge or not,
    num(int): the number of words splitted,
    Returns:
        documentId : String
    """

    doc = find_doc(input['userId'],input['doc'])
    if doc:
        doc_dict = doc[0]
        logging.debug("✅document found")
        return doc_dict['id']
    logging.debug("✅document doesn't found")
    #マークダウン化する
    doc = input["doc"]
    md = docToMd(doc)
    if doc["type"] == "url":
        url = doc["detail"]
    else:
        url = None #images in document doen't be extracted
    jsonList = mdToJson(md,url)
    mdDicts,mdraws = jsonToMdList(jsonList,limitPerDoc,num)
    logging.debug("✅inputs changed to md")
    userId = input['userId']
    source = get_source(input['doc'])
    docTitle = input['title']
    docId,contentIds = init_doc_firebase(docTitle,mdDicts,userId,source,mdraws)    
    logging.debug(f'✅init document to firebase,docId:{docId}')
    await init_summary_firebase(docTitle,md,userId,source,num,docId,contentIds)
    update_doc_to_firestore(docId,{'summaryState':'ready'})
    return docId


async def doSearch(userId,contentId,md,docId,vector,num = 200,threshold = 0.25):
    """
    Args:
        userId: str (e.g. "cyC421CyMJlC7B2")
        contentId: str  (e.g. "djkdheiklB2")
        md: str (e.g. "###こんにちは\n\n私は...")
        docId: str  (e.g. "duiwvheiklB2")
        vector: list
        num: int 
        threshold: float
    Returns:
        None
    """

    #ベクトルを取得
    logging.info(f"✅vector search started at contentId{contentId}")
    searchResults = vector_search(vector,userId,docId,threshold=threshold,limit=1) #ベクトル探索
    searchResults_list = list(searchResults) #探索結果をリスト化して要素があればhit
    if searchResults_list:
        result_dict = searchResults_list[0].to_dict() #結果を辞書にする
        knowledgeId = result_dict['id']
        knowledgeMd = result_dict['content']
        summaryId = result_dict['summaryId']
        logging.info(f'✅knowledge found knowledgeId: {knowledgeId}, contentId: {contentId}summaryId:{summaryId}')
        newMd,title,rate,removedInfo = await removeInfo(md,knowledgeMd)
        if newMd is None:#新情報がなかった場合
            new_content = {'state':'ready'}
            update_content_to_firestore(contentId,new_content)
            logging.info(f'✅there are no new contents at all contentId:{contentId}')
        elif rate < 10:
            new_content = {'state':'ready'}
            update_content_to_firestore(contentId,new_content)
            logging.info(f'✅there are no new contents at all contentId:{contentId}')
        elif rate == 100:#完全に新しい情報だった場合
            new_content = {'state':'ready','type':'known','knowledgeId':knowledgeId,'summaryId':summaryId,'removedInfo':removedInfo,'efficiency':rate}
            update_content_to_firestore(contentId,new_content)
            logging.info(f'✅all information are known contentId:{contentId} , knowledgeId: {knowledgeId}')
        else:#一部新しい情報があった場合
            new_content = {'type':'mdEdited','detail':newMd,'state':'ready','original':md,'knowledgeId':knowledgeId,'efficiency':rate,'removedInfo':removedInfo,'summaryId':summaryId} #contentを更新
            update_content_to_firestore(contentId,new_content)
            logging.info(f'✅merged knowledgeId: {knowledgeId}, contentId: {contentId}')
    else:
        new_content = {'state':'ready'}
        update_content_to_firestore(contentId,new_content)
    logging.info(f'🍺Done contentId: {contentId}')


#markdown
def docToMd(input:dict)->str:
    """
    Args:
        input(dict):json形式
            (e.g.){'type':'url','detail':"https://zenn.dev/hackathons/2024-google-cloud-japan-ai-hackathon"}
    Return:
        md(str):マークダウン       

    """
    if input['type'] == 'url':
        url = input['detail']
        md = MarkItDown()
        result = md.convert(url)
        md_text = result.text_content
        return md_text
    elif  input['type'] == 'xlsx' or input['type'] == 'pptx' or input['type'] == 'docx':
        url = input['detail']
        content = get(url).content
        data = BytesIO(content)
        temp_filename = "temp_pdf_file"+input['type']
        with open(temp_filename, "wb") as temp_file:
            temp_file.write(data.getvalue())
        md = MarkItDown()
        result = md.convert(temp_filename)
        md_text = result.text_content
        os.remove(temp_filename)
        return md_text
    elif input['type'] == 'md' or input['type'] == 'txt':
        url = input['detail']
        content = get(url).content
        detected = detect(content)
        encoding = detected['encoding']
        text = content.decode(encoding)
        return text
    elif input['type'] == 'pdf':
        url = input['detail']
        content = get(url).content
        data = BytesIO(content)
        temp_filename = "temp_pdf_file.pdf"
        with open(temp_filename, "wb") as temp_file:
            temp_file.write(data.getvalue())
        md_text = pymupdf4llm.to_markdown(temp_filename)
        os.remove(temp_filename)
        return md_text    


def chunkingMd(md:str,min:int=50,max:int=150):
    chunks = []
    
    last_newline_index = md.find("#") # 最初の#までの部分を取り出す
    chunks.append(md[:last_newline_index]) 

    data = md[last_newline_index:] # 最初の#以降の部分を取り出す
    data_strip = re.findall(r'#+ .*?(?=[ |\n]#+ |$)',data, flags=re.DOTALL) # MDの見出しごとに分割
    i = 0
    
    while i < len(data_strip):
        section = data_strip[i]

        if len(section) < min: # min文字以下の場合、次の見出しと結合

            if i+1 < len(data_strip):
                data_strip[i] = section + data_strip[i+1]
                del data_strip[i+1]
            else: #もし最後の要素だったらそのままchunksに入れる
                chunks.append(section)
                i += 1
        elif len(section) > max: # max文字以上の場合は分割
            while len(section) > max:
                index = find_last_index(section[:max]) #max文字以下で最長の区切り文字(['。','.','\n','?','!','！','？'])で分割する
                if index == -1: #もし改行文字がなければmax文字で分割する
                    index = max-1
                chunks.append(section[:index+1])
                section = section[index+1:]
            if len(section) < min:
                data_strip[i] = section
            else:
                chunks.append(section)
                i += 1
        else:
            chunks.append(data_strip[i])
            i += 1
    return chunks

def jsonToMdList(jsonList: list[dict],limitPerDoc:int=7000,num:int=200) -> list[str]:
    """
    Args:
        jsonList: list of dict
            {
                'type': "heading" | "paragraph" | "image" | "list" | "list_item" | softbreak | ...,
                'text': markdown text,
                'url': image url,
                'raw': raw AST
                'context': context text
            }[],
        limitPerDoc: the number of words splitted
        num: the number of words splitted
    Returns:
        list of str: list of dict with following format
            {
                'type': "mdraw"|"heading" | "paragraph" | "image" | "list" | "list_item" | softbreak | ...,
                'text': markdown text,
                'url': image url,
                'raw': raw AST
                'context': context text
            }[],        
        mdraws : list of markdown which is categorized as "mdraw",

        "mdraw" means markdown which will be processed by vector search
    """
    mdDicts = []
    count = 0
    contextNum = num //2
    contextBefore = ""
    contextAfter = ""
    mdraws = []
    for mdjson in jsonList:
        if (mdjson["type"] == "heading") or (mdjson["type"] == "paragraph"): #contextを取得
            contextBefore += mdjson["text"]
            if len(contextBefore) > contextNum:
                contextBefore = contextBefore[-contextNum:]
        
        if mdjson["type"] == "paragraph": #text関係
            if len(mdjson["text"]) < MINLEN: #MINLEN文字以下だったら箇条書きなどと判定して処理しない
                mdDicts.append(mdjson)
            else:
                count += len(mdjson["text"])
                if count < limitPerDoc:#制限文字数以下なら処理する
                    texts = chunkingMd(mdjson["text"],min = num - 50,max = num + 50)
                    for content in texts:
                        mdDicts.append({"type":"mdraw","text":content,"context":contextBefore}) #mdrawは処理されるべきデータ
                    mdraws.append(contextBefore+ "\n" + content)
                else:#文字数
                    mdDicts.append(mdjson)
        else: #link関係,#list関係など処理しない
            mdDicts.append(mdjson)
    return mdDicts,mdraws

def mdToJson(text:str,url:str=None):
    """
    make Json from mistune converter
    Args:
        markdown: markdown text,
        url, original url
    Returns:
        list: chunked markdown text,
            {
                'type': "heading" | "paragraph" | "image" | "list" | "list_item" | softbreak | ...,
                'text': markdown text,
                'url': image url,
                'raw': raw AST
            }[]

    """
    markdown = mistune.create_markdown(renderer='ast')
    tokens = markdown(text)
    renderer = MarkdownRenderer()

    mdChunked = []
    for token in tokens:
        flag_list = False
        if token["type"] == "paragraph": #paragraphの中にimageがある場合がある
            children_temp = []
            for child in token["children"]: #imageの中のURLを相対から絶対に変換
                if flag_list:
                    children_temp.append(child)
                    continue
                if child["type"] == "image":
                    if children_temp:#それ以前の内容を処理
                        markdown_text = renderer(children_temp, state=BlockState())
                        mdChunked.append({'type': "paragraph", 'text': markdown_text})
                        children_temp = []

                    resolvedURL = resolve_path(url,child['attrs']['url'])
                    child['attrs']['url'] = resolvedURL
                    markdown_text = renderer([child], state=BlockState()) #AST->MD
                    mdChunked.append({'type': "image", 'text': markdown_text,'url':child['attrs']['url'],'raw':child})   
                elif child["type"] == "link":
                    if 'children' in child:
                        grandchild = child['children'][0] #linkの中のtextを取得
                        if grandchild["type"] == "image": #linkではなくimageとして処理
                            if children_temp:#それ以前の内容を処理
                                markdown_text = renderer(children_temp, state=BlockState())
                                mdChunked.append({'type': "paragraph", 'text': markdown_text})
                                children_temp = []

                            resolvedURL = resolve_path(url,grandchild['attrs']['url'])
                            grandchild['attrs']['url'] = resolvedURL
                            markdown_text = renderer([grandchild], state=BlockState()) #AST->MD
                            mdChunked.append({'type': "image", 'text': markdown_text,'url':child['attrs']['url'],'raw':child})   
                        else:       
                            children_temp.append(grandchild)                  
                else:
                    if (child["type"] == "text") and (child["raw"][0] == "|"):#tableの場合
                        if children_temp:
                            markdown_text = renderer(children_temp, state=BlockState())
                            mdChunked.append({'type': "paragraph", 'text': markdown_text})
                            children_temp = []
                        flag_list = True
                    children_temp.append(child)   
            if flag_list:
                mdChunked.append({'type': "list", 'text': renderer(children_temp, state=BlockState())})
            else:
                mdChunked.append({'type': "paragraph", 'text': renderer(children_temp, state=BlockState())})
        else:
            markdown_text = renderer([token], state=BlockState()) #AST->MD
            mdChunked.append({'type': token["type"], 'text': markdown_text})
    return mdChunked

def resolve_path(path1: str, path2: str) -> str:
    """
    Resolve path2 relative to path1 if path2 is a relative path.

    Parameters:
        path1 (str): The base absolute path (e.g., URL).
        path2 (str): The path to resolve (absolute or relative).

    Returns:
        str: An absolute path.
    """
    # If path2 starts with 'http', return it as is (absolute path)
    if path2.startswith("http"):
        return path2

    # Otherwise, resolve path2 relative to path1
    return urljoin(path1, path2)

def find_last_index(text):
    """
    Find the index of the last occurrence of any character in `terminators` in the given `text`.

    :param text: The input string.
    :param terminators: A string of characters to be treated as terminators.
    :return: The index of the last occurrence of any terminator, or -1 if none are found.
    """
    last_index = -1
    terminators = ['。','\n','?','！','？']
    for terminator in terminators:
        index = text.rfind(terminator)  # Find the last occurrence of the terminator
        if index > last_index:
            last_index = index
    return last_index

def get_title(doc:dict,title)->str:
    """
    Args:
        doc(dict): 
        { type : url | pdf | xlsx | pptx | docx | md | txt,
        detail : https//... | ###こんにちは\n\n私は...,
        }
        title : title(other than url),
    Returns:
        title(str)
    """
    if doc['type'] == 'url':
        response = req.urlopen(doc['detail'])
        parse_html = BeautifulSoup(response, "html.parser")
        title = parse_html.title.string
        return title
    else:
        return  title
  
def get_source(doc:dict)->str:
    """
    Args:
        doc:    {'type':(e.g. 'url')
                'detail':(e.g. 'https://...')
                }
    Retrun: source: {'type':(e.g. 'url')
                'detail':(e.g. 'https://...')
                }
    """
    return doc
    

#embedding
def text_to_vector(texts: list = None,dimensionality:int = 256,task:str = "SEMANTIC_SIMILARITY") -> list[list[float]]:
    """Embeds texts with a pre-trained, foundational model.
    Inputs:
    texts:
        list of texts
    dimentionality :
        The dimensionality of the output embeddings.

    Returns:
        A list of lists containing the embedding vectors for each input text
    """
    
    # The task type for embedding. Check the available tasks in the model's documentation.
     #テキストの類似度に最適化

    model = TextEmbeddingModel.from_pretrained("text-multilingual-embedding-002")
    inputs = [TextEmbeddingInput(text, task) for text in texts]
    kwargs = dict(output_dimensionality=dimensionality) if dimensionality else {}
    embeddings = model.get_embeddings(inputs, **kwargs)

    return [embedding.values for embedding in embeddings]

#gemini
async def removeInfo(md_chunked:str,knowledge:str):
    """
    Args:
        md_chunked(str) : markdown raw data,
        knowledge(str) : knowledge with markdown,
    Returns:
        result(str): result markdown
        title(str):title markdown
    """

    model = GenerativeModel("gemini-1.5-flash")

    #MDを情報単位に分割
    response_schema = {
        "type": "array",
        "items": {
            "type": "object",
            "properties": {
                "title": {
                    "type": "string",
                },
                "content": {
                    "type": "string",
                },
            },
            "required": ["title","content"],
        },
    }
    generation_config=GenerationConfig(
        response_mime_type = "application/json", 
        response_schema=response_schema,
        max_output_tokens = 8192,
        temperature= 1,
        top_p = 0.95
    )
    prompt = f"""
    {md_chunked}

    In response to the above, please state what you have learned in {LANGUAGE}, no matter how slight the content is, as many as possible.
    Specifically, create an object of the following form
    list of objects:
        - title"`: Title
        - content"`: One thing you learned in {LANGUAGE}

    """
    response_part1 = await model.generate_content_async(
        [prompt],
        generation_config=generation_config,
        safety_settings=safety_settings,
        stream=False,
    )
    response_part1 = json.loads(response_part1.text)

    logging.info(f"✅response_part1:{response_part1}")
    #情報単位で知識内に情報があるか調べる
    response_schema = {
        "type": "array",
        "items": {
            "type": "object",
            "properties": {
                "sentenceNo": {
                    "type": "integer",
                },
                "result": {
                    "type": "string",
                },
            },
            "required": ["sentenceNo","result"],
        },
    }

    generation_config=GenerationConfig(
        response_mime_type = "application/json", 
        response_schema=response_schema,
        max_output_tokens = 8192,
        temperature= 1,
        top_p = 0.95
    )
    prompt = f"""
    {knowledge}
    QUESTION:
    Are any of the following statements mentioned in the above document? 
    Please output a Yes or No for each statement in the following format.
    Statements:
    """
    for i in range(len(response_part1)):
        prompt += f"\nstatement{i+1} :{response_part1[i]["title"]},{response_part1[i]["content"]}"

    last = """
    出力形式:
    - sentenceNo: the number of statement(Int)
    - result : "YES" | "NO"
    """
    prompt += last

    response_part2 = await model.generate_content_async(
        [prompt],
        generation_config=generation_config,
        safety_settings=safety_settings,
        stream=False,
    )
    response_part2 = json.loads(response_part2.text)


    newSentences = []
    removedContents = []

    for i in range(len(response_part1)):
        if response_part2[i]["result"] != "YES":
            newSentences.append(response_part1[i]["content"])
        else:
            removedContents.append(response_part1[i]["content"])


    if len(newSentences) ==  len(response_part1):
        return None,None,None,None
    

    if newSentences:
        #既知の情報の結合をする
        response_schema = {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "title": {
                        "type": "string",
                    },
                    "summary": {
                        "type": "string",
                    },
                },
                "required": ["title","summary"],
            },
        }
        generation_config=GenerationConfig(
            response_mime_type = "application/json", 
            response_schema=response_schema,
            max_output_tokens = 8192,
            temperature= 1,
            top_p = 0.95
        )

        prompt = f"""
        {md_chunked}

        Based on the above, simply summarize the following in a natural connection in {LANGUAGE} in a simple markdown format.
        The summary should consist of approximately {len(newSentences)} sentences.


        """
        for newSentence in newSentences:
            prompt += "\n"+newSentence


        response_part3 = await model.generate_content_async(
            [prompt],
            generation_config=generation_config,
            safety_settings=safety_settings,
            stream=False,
        )

        response_part3 = json.loads(response_part3.text)

        result = response_part3[0]["summary"]
        title = response_part3[0]["title"]
        rate = int((1 - len(result)/len(md_chunked)) * 100)
        if rate < 0:
            return None,None,None,None
    else:
        #全て既知の情報
        result = None
        title = None
        rate = 100

    
    
    return result,title,rate,removedContents

async def getKnowledge(md:str,num:int,prof :str = None,language:str=LANGUAGE):
    """
    Args:
        md(str) : markdown raw data,
        num(int): the number of words each section will have,
    Returns:
        knowledges(list): a list of knowledges with following format,
                    "properties": {
                "title": {
                    "type": "string",
                },
                "section": {
                    "type": "string",
                },
            },
    """
    
    model = GenerativeModel(
        model_name="gemini-1.5-flash-002",
    )


    response_schema = {
        "type": "array",
        "items": {
            "type": "object",
            "properties": {
                "title": {
                    "type": "string",
                },
                "section": {
                    "type": "string",
                },
            },
            "required": ["title","section"],
        },
    }

    generation_config=GenerationConfig(
        response_mime_type = "application/json", 
        response_schema=response_schema,
        max_output_tokens = 8192,
        temperature= 1,
        top_p = 0.95
    )    

    prompt = f"""
    {md}
    Summarize the text in the markdown format above.
    Please create chapters for your summary and create a title for each chapter.
    Each chapter should be written in {language} in {int(num/30)} sentences.
    The output should be in the following JSON format.
    - `“title”`: title of each section
    - `“section”`: A summarized paragraph in {int(num/30)} sentences in {language}
    """

    response_part = await model.generate_content_async(
        [prompt],
        generation_config=generation_config,
        safety_settings=safety_settings,
        stream=False,
    )
    response_part = json.loads(response_part.text)



    #make system message again
    response_schema = {
        "type": "object",
        "properties": {
            "section": {
                "type": "string",
            },
        },
        "required": ["section"],
    }
    generation_config=GenerationConfig(
        response_mime_type = "application/json", 
        response_schema=response_schema,
        max_output_tokens = 8192,
        temperature= 1,
        top_p = 0.95
    )    
    get_responses  = []
    for response in response_part:
        md = response["section"]
        prompt = f"""
        {md}
        Please convert the content of the above text for users in the following preferences.
        User's preferences:
        {prof}


        The output should be written in {language}.
        The output should be in the following JSON format.
        - `“section”`: A converted paragraph in {language}
        """
        get_responses.append(model.generate_content_async(
            [prompt],
            generation_config=generation_config,
            safety_settings=safety_settings,
            stream=False,
        ))


    response_parts = await asyncio.gather(*get_responses)

    new_response_parts = []
    for i in range(len(response_part)):
        new_response_parts.append({"title":response_part[i]["title"],"section":json.loads(response_parts[i].text)["section"]})

    return new_response_parts,response_part

async def makeProf(prof:str,language:str):
    """
    Args:
        prof:str (user input of profile)
    Returns:
        profile:str (gemini modified profile),
        language:str(gemini guessed)
    """
    model = GenerativeModel("gemini-1.5-flash")

    response_schema = {
        "type": "object",
        "properties": {
            "preference": {
                "type": "string",
            },
            "language":{
                "type":"string"
            }
        },
        "required": ["preference","language"],
    }

    generation_config=GenerationConfig(
        response_mime_type = "application/json", 
        response_schema=response_schema,
        max_output_tokens = 8192,
        temperature= 1,
        top_p = 0.95
    )    

    prompt = f"""
    language the user speaks : {language}
    preferences : {prof}
    This is the result of asking users to enter their preference and language in the form of a questionnaire.
    Please consider this statement and describe this person's request in English.
    If there is not enough information or the preference is incomprehensible and you cannot describe, please output the following: “This person likes general expression."
    Also, please use the information from this questionnaire to identify the language the user speaks in English.
    """
    response_part = await model.generate_content_async(
        [prompt],
        generation_config=generation_config,
        safety_settings=safety_settings,
        stream=False,
    )
    response_part = json.loads(response_part.text)
    return response_part['preference'],response_part['language']

#firebase
def create_profiles_to_firestore(userId:str,profile:str,language:str):
    """
    Args: 
    userId(str): userId,
    profile(str):gemini create profile
    language(str):gemini create language

    
    """

    # 新しいドキュメントをprofilesコレクションに追加
    doc_ref = db.collection("profiles").document(userId)
    doc_ref.set({
        "id": doc_ref.id,
        "profile" : profile,
        "language" : language,
    })

    return doc_ref.id


def save_knowledges_to_firestore(title: str, content: str, vector: list,sources: list,userId: str):
    """
    Save knowledge information to the Firestore database(collection: knowledges).

    Args:
        title (str): The title of the knowledge entry.
        vector (list): The vector representation of the knowledge entry.
        content (str): The content of the knowledge entry.
        sources (list): The sources of the docuent with following format:
            [
                {
                    "type": str (e.g. "book", "website","pdf"),
                    "detail": str (e.g. "https://example.com")
                },
                ...
            ]
        userId (str): The user ID of the knowledge entry.
    """

    # 新しいドキュメントをknowledgeコレクションに追加
    doc_ref = db.collection("knowledges").document()
    doc_ref.set({
        "id": doc_ref.id,
        "vector": Vector(vector),
        "title": title,
        "content": content,
        "createdAt": firestore.SERVER_TIMESTAMP,
        "sources": sources,
        "userId": userId
    })

    return doc_ref.id

def save_docs_to_firestore(title: str, contents: list,userId: str,source: dict,state:str,summaryState:str = "init",summaryId:str = None):
    """
    Save document information to the Firestore database(collection: docs).

    Args:
        title (str): The title of the knowledge entry.
        contents (list): a list of contentId :
        userId (str): The user ID of the knowledge entry.
        source (str): The source of the document with following format:
            {
                "type": str (e.g. "book", "website","pdf"),
                "detail": str (e.g. "https://example.com")
            }
        state (str): init,processing,ready 
    Return:
        docmentId(str)
    """

    # 新しいドキュメントをknowledgeコレクションに追加
    doc_ref = db.collection("docs").document()
    doc_ref.set({
        "title": title,
        "contents": contents,
        "createdAt": firestore.SERVER_TIMESTAMP,
        "userId": userId,
        "id": doc_ref.id,
        "source": source,
        "state":state,
        "summaryState" : summaryState,
        "summaryId":summaryId
    })

    return doc_ref.id

def save_contents_to_firestore(docId:str,type:str,detail:str,state:str,original:str = None,knowledgeId:str = None,userId:str=None,summaryId:str = None):
    """
    Save content information to the Firestore database(collection: docs).

    Args:
        docId (str) : documentId
        type (str) mdRaw | mdEdited :
        detail (str) : markdown
        state (str): init | ready 
        original (str) : raw MD data (only mdEdited)
        knowledgeId (str) : knowledgeId (only mdEdited)
        userId(str):userId
    Return:
        contentId(str)
    """
    
    # 新しいドキュメントをknowledgeコレクションに追加
    doc_ref = db.collection("contents").document()
    doc_ref.set({
        "docId" : docId,
        "type": type,
        "id": doc_ref.id,
        "detail": detail,
        "state":state,
        "original" : original,
        "knowledgeId" : knowledgeId,
        "createdAt" : firestore.SERVER_TIMESTAMP,
        "userId":userId,
        "summaryId" : summaryId
    })

    return doc_ref.id

def save_inputs_to_firestore(type:str,detail:str,userId:str):
    """
    Save content information to the Firestore database(collection: docs).

    Args:
        "type": str (e.g. "book", "website","pdf"),
        "detail": str (e.g. "https://example.com")
        "userId" :str

    Return:
        inputId(str)
    """
    
    # 新しいドキュメントをknowledgeコレクションに追加
    doc_ref = db.collection("inputs").document()
    doc_ref.set({
        "type": type,
        "id": doc_ref.id,
        "detail": detail,
        "createdAt" : firestore.SERVER_TIMESTAMP,
        "userId":userId
    })

    return doc_ref.id

def save_summaries_to_firestore(title: str, knowledges: list,userId: str,source: dict,state:str,docId:int):
    """
    Save document information to the Firestore database(collection: docs).

    Args:,
        title (str): The title of the knowledge entry.,
        knowledges (list): a list of knowledgeId :,
        userId (str): The user ID of the knowledge entry.,
        source (str): The source of the document with following format:,
            {,
                "type": str (e.g. "book", "website","pdf"),
                "detail": str (e.g. "https://example.com"),
            },
        state (str): init,processing,ready ,
    Return:,
        docmentId(str)
    """

    # 新しいドキュメントをknowledgeコレクションに追加
    doc_ref = db.collection("summaries").document()
    doc_ref.set({
        "title": title,
        "knowledges":knowledges,
        "createdAt": firestore.SERVER_TIMESTAMP,
        "userId": userId,
        "id": doc_ref.id,
        "source": source,
        "state":state,
        "docId":docId,
    })

    return doc_ref.id

def vector_search(vector: list, userId: str, docId:str,threshold: int = 0.2, limit: int = 1):
    """
    Perform a vector search in the Firestore database with an exclusion condition.
    
    Args:
        vector (list): The vector representation of the query (256-dimensional vector).
        userId (str): The user ID to filter knowledge entries.
        threshold (int): The similarity threshold for the search.
        limit (int): The maximum number of results to return.
        exclude_doc_id (str): The document ID to exclude from the search (optional).
    
    Returns:
        dict: The nearest knowledge entry to the query vector.
    """
    collection = db.collection("knowledges")
    
    # Create the base query
    query = collection.where("userId", "==", userId)
    
    # Add exclusion condition for docId if provided
    
    query = query.where("docId", "!=", docId)  # Firestore supports "!=" for indexed fields
    
    # Add vector search condition
    vector_query = query.find_nearest(
        vector_field="vector",
        query_vector=Vector(vector),
        distance_measure=DistanceMeasure.COSINE,
        limit=limit,
        distance_result_field="vector_distance",
        distance_threshold=threshold,
    )

    return vector_query.stream()

def update_knowledges_to_firestore(knowledgeId:int,content:dict):
    """
    知識データをupdateする
    Args:
        knowledgeId(int): 更新する知識データID
        content(dict):更新する内容
            (e.g.)
            {"title":"更新するタイトル",
            "vector":"更新するベクトル"
            ...
            }
    """
    doc_ref = db.collection("knowledges").document(knowledgeId)
    doc_ref.update(content)

    return knowledgeId

def update_doc_to_firestore(docId:int,content:dict):
    """
    記事データをupdateする
    Args:
        docId(int): 更新するdocumentID
        content(dict):更新する内容
            (e.g.)
            {"title":"更新するタイトル",
            ...
            }
    """
    doc_ref = db.collection("docs").document(docId)
    doc_ref.update(content)
    return docId

def update_content_to_firestore(contentId:int,content:dict):
    """
    記事データをupdateする
    Args:
        contentId(int): 更新するcontentID
        content(dict):更新する内容
            (e.g.)
            {"title":"更新するタイトル",
            ...
            }
    content examples
        docId (str) : documentId
        type (str) mdRaw | mdEdited :
        detail (str) : markdown
        state (str): init | ready 
        original (str) : raw MD data (only mdEdited)
        knowledgeId (str) : knowledgeId (only mdEdited)
    
    Return:
        contentId(str)
    
    """

    doc_ref = db.collection("contents").document(contentId)
    doc_ref.update(content)
    return contentId

def update_input_to_firestore(inputId:int,content:dict):
    """
    記事データをupdateする
    Args:
        docId(int): 更新するdocumentID
        content(dict):更新する内容
            (e.g.)
            {"title":"更新するタイトル",
            ...
            }
    """
    doc_ref = db.collection("inputs").document(inputId)
    doc_ref.update(content)
    return inputId

def update_profiles_to_firestore(userId:int,content:dict):
    """
    記事データをupdateする
    Args:
        docId(int): 更新するdocumentID
        content(dict):更新する内容
            (e.g.)
            {"title":"更新するタイトル",
            ...
            }
    """
    doc_ref = db.collection("users").document(userId)
    doc_ref.update(content)
    return userId


def init_doc_firebase(title: str, jsons: list,userId: str,source: dict,mdraws:list):
    """
    Save knowledge information to the Firestore database(collection: docs).

    Args:
        title (str): The title of the knowledge entry.,
        jsons (list): json list of markdown,
            {
            "type"(str) : text | link | raw:(raw is the data which will not be processed by gemini due to limitation)
            "text"(str): md
            }
        userId (str): The user ID of the knowledge entry.,
        source (str): The source of the document with following format:,
            {
                "type": str (e.g. "book", "website","pdf"),
                "detail": str (e.g. "https://example.com")
            }
        mdraws : a list of markdown which is categorized as "mdraw"
    Return;
        docId: documentId,
        contents : a list of contentId
    """
    contents = []
    docId = save_docs_to_firestore(title,contents,userId,source,"init",summaryState="init",summaryId="None")
    vectors = text_to_vector(mdraws,task = "RETRIEVAL_QUERY")
    logging.info(f"✅vector created at docId:{docId}")
    batch = db.batch()
    batch_timing = 4
    count = 0
    mdraw_index = 0
    for json in jsons:
        if count == batch_timing:
            batch.commit()
            batch = db.batch()
            batch_timing *= 4
            count = 0
        json_type = json["type"]
        md = json["text"]
        content_ref = db.collection("contents").document()
        if json_type == "mdraw":
            content = {
                "docId" : docId,
                "type": 'mdRaw',
                "id": content_ref.id,
                "detail": md,
                "state":'init', #mdrawの場合はinit
                "createdAt" : firestore.SERVER_TIMESTAMP,
                "original" : md,
                "knowledgeId" : None,
                "userId":userId,
                "mdType":json_type,
                "summaryId":"None",
                "context":json["context"],
                "vector" : vectors[mdraw_index]
            }
            mdraw_index += 1
        else: #type == "link","raw"
            content = {
                "docId" : docId,
                "type": 'mdRaw',
                "id": content_ref.id,
                "detail": md,
                "state":'ready',
                "createdAt" : firestore.SERVER_TIMESTAMP,
                "original" : md,
                "knowledgeId" : None,
                "userId":userId,
                "mdType":json_type,
                "summaryId":"None",
            }

        batch.set(content_ref, content)
        contents.append(content_ref.id)
        count += 1

    
    doc_ref = db.collection("docs").document(docId)
    batch.update(doc_ref,{'contents':contents,'state':'ready'})
    batch.commit()
    return docId,contents

async def init_summary_firebase(title: str, md: str,userId: str,source: dict,num:int,docId:int,contentIds:list):
    """
    Save knowledge information to the Firestore database(collection: docs).

    Args:
        title (str): The title of the knowledge entry.,
        md (str): md ,
        userId (str): The user ID of the knowledge entry.,
        source (str): The source of the document with following format:,
            {,
                "type": str (e.g. "book", "website","pdf"),
                "detail": str (e.g. "https://example.com"),
            },
        num(int): the number of words each knowledge will have,
        contentIds(list): a list of contentId
    Return;
        sumId: summaryId,
    """
    print(f"✅start making summary")
    knowledges = []
    sumId = save_summaries_to_firestore(title,knowledges,userId,source,"init",docId)
    print(f"✅summary created{sumId}")
    details=[]
    profiles = get_profiles(userId)
    logging.info(f"{profiles["profile"]},{profiles["language"]}")
    sections,raw_sections = await getKnowledge(md,num,profiles['profile'],profiles['language'])
    print(f"got knowledge")
    for section in raw_sections:
        details.append(section["section"])
    vectors = text_to_vector(details,task = "RETRIEVAL_DOCUMENT")
    print(f"got vectors")

    batch = db.batch()
    for section,vector in zip(sections,vectors):
        content_ref = db.collection("knowledges").document()
        content = {
            "summaryId" : sumId,
            "content" : section["section"],
            "id": content_ref.id,
            "vector": Vector(vector),
            "createdAt" : firestore.SERVER_TIMESTAMP,
            "updatedAt" : firestore.SERVER_TIMESTAMP,
            "userId":userId,
            "score":50,
            "title":section["title"],
            "sources":[source],
            "docId":docId,
        }

        batch.set(content_ref, content)
        knowledges.append(content_ref.id)
    
    doc_ref = db.collection("summaries").document(sumId)
    batch.update(doc_ref,{'knowledges':knowledges,'state':"ready"})
    doc_ref = db.collection("docs").document(docId)
    batch.update(doc_ref,{"summaryId":sumId})
    batch.commit()
    return sumId

def find_doc(user_id, source):
    """
    userIdとsourceからドキュメントを検索する
    Args:
        user_id :String
        source :String  
    Return:
        document data(dict) from firebase
    """
    doc_ref = db.collection("docs")
    # 複数条件のクエリ
    query_ref = doc_ref.where("userId", "==", user_id).where("source", "==", source)
    docs = query_ref.get()
    return [doc.to_dict() for doc in docs]  # ドキュメントの内容を辞書形式で返す

def get_doc(docId:str)->dict:
    """
    Args:
        docId :String
    Return:
        document data(dict) from firebase 
    """
    doc_ref = db.collection("docs").document(docId)
    doc = doc_ref.get()
    return doc.to_dict()

def get_summary(sumId:str)->dict:
    """
    Args:
        sumId :String
    Return:
        summary data(dict) from firebase 
    """
    doc_ref = db.collection("summaries").document(sumId)
    doc = doc_ref.get()
    return doc.to_dict()

def get_content(contentId:str)->dict:
    
    """
    Args:
        contentId :String
    Return:
        content data(dict) from firebase 
    """
    doc_ref = db.collection("contents").document(contentId)
    doc = doc_ref.get()
    return doc.to_dict()

def get_input(inputId:str)->dict:
    """
    Args:
        inputId :String
    Return:
        input data(dict) from firebase 
    """
    doc_ref = db.collection("inputs").document(inputId)
    doc = doc_ref.get()
    return doc.to_dict()
      
def get_profiles(userId:str)->dict:
    
    """
    Args:
        userId :String
    Return:
        content data(dict) from firebase 
    """
    doc_ref = db.collection("profiles").document(userId)
    doc = doc_ref.get()
    return doc.to_dict()

def deleteContents(contentIds:list):
    """
    Args:
        contentIds :list
    Return:
        None
    """
    batch = db.batch()
    for contentId in contentIds:
        content_ref = db.collection("contents").document(contentId)
        batch.delete(content_ref)
    logging.info("✅Deletion complete.(contents)")
    batch.commit()

def deleteKnowledges(knowledgeIds:list):
    """
    Args:
        knowledgeIds :list
    Return:
        None
    """
    batch = db.batch()
    for knowledgeId in knowledgeIds:
        knowledge_ref = db.collection("knowledges").document(knowledgeId)
        batch.delete(knowledge_ref)
    logging.info("✅Deletion complete.(knowledges)")
    batch.commit()

def extract_ids(data):
    """
    Extracts a list of IDs from the provided data.

    Parameters:
        data (dict): Input dictionary containing 'values' with 'stringValue'.

    Returns:
        list: A list of IDs extracted from 'stringValue'.
    """
    return [item['stringValue'] for item in data.get('values', [])]