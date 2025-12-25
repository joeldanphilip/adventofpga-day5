import sys

def parse_input(filename):
    ranges = []
    candidates = []
    reading_ranges = True
    
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            
            # Switch mode on empty line
            if not line:
                if reading_ranges:
                    reading_ranges = False
                continue
            
            if reading_ranges:
                # Parse Range "10-20"
                start, end = map(int, line.split('-'))
                ranges.append((start, end))
            else:
                # Parse Candidate "123"
                candidates.append(int(line))
                
    return ranges, candidates

def solve():
    print("Reading input.txt...")
    ranges, candidates = parse_input("input.txt")
    print(f"Parsed {len(ranges)} ranges and {len(candidates)} candidates.")
    
    count = 0
    for cand_id in candidates:
        # Check if ID is in ANY valid range
        is_fresh = any(start <= cand_id <= end for start, end in ranges)
        if is_fresh:
            count += 1
            
    print("-" * 30)
    print(f"PYTHON REFERENCE ANSWER: {count}")
    print("-" * 30)

if __name__ == "__main__":
    solve()