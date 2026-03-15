import os
from typing import List

import chromadb
from fastembed import TextEmbedding

# The pre-trained model used to convert text into numerical vectors.
EMBEDDING_MODEL_NAME = "BAAI/bge-small-en-v1.5"
# The local directory where the vector database is stored.
CHROMA_DB_DIR = os.path.join(os.path.dirname(__file__), "chroma_db")
# The name of the collection within ChromaDB to store resume data.
COLLECTION_NAME = "resume_chunks"
# The number of text chunks processed at once during embedding.
ENCODE_BATCH_SIZE = 32
# The number of vectors saved to the database in a single transaction.
DB_ADD_BATCH_SIZE = 100


def chunk_text(text: str, max_chars: int = 500) -> List[str]:
    """Split the input text into semantically coherent chunks."""
    text = text.strip()
    if not text:
        return []

    paragraphs = text.split("\n\n")
    chunks: List[str] = []
    current = ""

    def flush_current():
        nonlocal current
        if current.strip():
            chunks.append(current.strip())
        current = ""

    for para in paragraphs:
        para = para.strip()
        if not para:
            continue

        if len(current) + len(para) + 2 > max_chars:
            if len(para) > max_chars:
                lines = para.split("\n")
                for line in lines:
                    line = line.strip()
                    if not line:
                        continue
                    if len(current) + len(line) + 1 > max_chars:
                        flush_current()
                    current = (current + " " + line).strip()
                flush_current()
            else:
                flush_current()
                current = para
        else:
            if current:
                current = current + "\n\n" + para
            else:
                current = para

    flush_current()
    return chunks


def load_resume_chunks(resume_path: str) -> List[str]:
    """Read the resume file and return a list of text chunks."""
    if not os.path.exists(resume_path):
        raise FileNotFoundError(f"Could not find resume file at {resume_path}")

    with open(resume_path, "r", encoding="utf-8") as f:
        text = f.read()

    chunks = chunk_text(text, max_chars=500)
    if not chunks:
        raise ValueError("No text chunks were created from the resume.")

    print(f"Loaded resume: {len(text)} characters, {len(chunks)} chunks.")
    return chunks


def compute_embeddings(chunks: List[str]) -> List[List[float]]:
    """Convert text chunks into numerical embedding vectors."""
    model = TextEmbedding(model_name=EMBEDDING_MODEL_NAME)
    all_embeddings: List[List[float]] = []

    print("Computing embeddings in batches...")
    for start in range(0, len(chunks), ENCODE_BATCH_SIZE):
        batch = chunks[start : start + ENCODE_BATCH_SIZE]
        for emb in model.embed(batch):
            all_embeddings.append(emb.tolist())
        print(f"  Encoded {min(start + ENCODE_BATCH_SIZE, len(chunks))}/{len(chunks)} chunks")

    return all_embeddings


def save_to_vector_store(chunks: List[str], embeddings: List[List[float]]) -> None:
    """Clear existing data and save new embeddings to ChromaDB."""
    os.makedirs(CHROMA_DB_DIR, exist_ok=True)
    client = chromadb.PersistentClient(path=CHROMA_DB_DIR)

    # Safely clear the collection by deleting and recreating it
    try:
        client.delete_collection(name=COLLECTION_NAME)
    except Exception:
        pass  # Collection likely doesn't exist yet

    collection = client.get_or_create_collection(name=COLLECTION_NAME)

    print("Storing embeddings in ChromaDB...")
    for start in range(0, len(chunks), DB_ADD_BATCH_SIZE):
        end = min(start + DB_ADD_BATCH_SIZE, len(chunks))
        collection.add(
            ids=[f"chunk-{i}" for i in range(start, end)],
            documents=chunks[start:end],
            embeddings=embeddings[start:end],
            metadatas=[{"index": i} for i in range(start, end)],
        )
        print(f"  Stored {end}/{len(chunks)} chunks")

    print(f"Successfully stored {len(chunks)} chunks at {CHROMA_DB_DIR}.")


def build_vector_store(resume_path: str = None) -> None:
    """Orchestrate the full ingestion pipeline from file to database."""
    if resume_path is None:
        resume_path = os.path.join(os.path.dirname(__file__), "resume.txt")

    # 1. Load and chunk the input file
    chunks = load_resume_chunks(resume_path)

    # 2. Generate embeddings for each chunk
    embeddings = compute_embeddings(chunks)

    # 3. Save everything to the database
    save_to_vector_store(chunks, embeddings)


def main() -> None:
    """Entry point for the embedding creation script."""
    build_vector_store()


if __name__ == "__main__":
    main()
