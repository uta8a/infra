#!/usr/bin/env -S deno run --allow-read --allow-write

import { parse } from "@std/yaml";

interface Service {
  name: string;
  platform: string[];
  environment: string[];
  deployed: boolean;
}

interface ReadmeYaml {
  service: Service;
}

interface ServiceInfo {
  directory: string;
  name: string;
  platform: string;
  environment: string;
  deployed: string;
}

async function main() {
  // Collect all readme.yaml files
  const readmeFiles: Array<[string, string]> = [];
  
  for await (const entry of Deno.readDir(".")) {
    if (entry.isDirectory && entry.name !== ".github") {
      const readmePath = `${entry.name}/readme.yaml`;
      try {
        await Deno.stat(readmePath);
        readmeFiles.push([entry.name, readmePath]);
      } catch {
        // File doesn't exist, skip
      }
    }
  }

  // Sort by directory name
  readmeFiles.sort((a, b) => a[0].localeCompare(b[0]));

  // Parse and collect service information
  const services: ServiceInfo[] = [];
  
  for (const [dirName, readmePath] of readmeFiles) {
    try {
      const content = await Deno.readTextFile(readmePath);
      const data = parse(content) as ReadmeYaml;
      
      if (data && data.service) {
        const service = data.service;
        services.push({
          directory: dirName,
          name: service.name || "N/A",
          platform: service.platform?.join(", ") || "",
          environment: service.environment?.join(", ") || "",
          deployed: service.deployed ? "✓" : "✗",
        });
      }
    } catch (error) {
      console.error(`Error reading ${readmePath}:`, error);
    }
  }

  // Generate markdown table
  const tableLines = [
    "<!-- BEGIN INFRA LIST -->",
    "## Infrastructure Services",
    "",
    "| Directory | Service Name | Platform | Environment | Deployed |",
    "|-----------|--------------|----------|-------------|----------|",
  ];

  for (const service of services) {
    tableLines.push(
      `| ${service.directory} | ${service.name} | ${service.platform} | ${service.environment} | ${service.deployed} |`
    );
  }

  tableLines.push("<!-- END INFRA LIST -->");
  const tableContent = tableLines.join("\n");

  // Read current README.md
  let readmeContent: string;
  try {
    readmeContent = await Deno.readTextFile("README.md");
  } catch {
    readmeContent = "# infra\n\nMy infrastructure configuration\n\n";
  }

  // Replace or append the table
  const beginMarker = "<!-- BEGIN INFRA LIST -->";
  const endMarker = "<!-- END INFRA LIST -->";

  let newReadme: string;
  if (readmeContent.includes(beginMarker) && readmeContent.includes(endMarker)) {
    // Replace existing table
    const startIdx = readmeContent.indexOf(beginMarker);
    const endIdx = readmeContent.indexOf(endMarker) + endMarker.length;
    newReadme = readmeContent.substring(0, startIdx) + tableContent + 
                readmeContent.substring(endIdx);
  } else {
    // Append new table
    if (!readmeContent.endsWith("\n")) {
      readmeContent += "\n";
    }
    newReadme = readmeContent + "\n" + tableContent + "\n";
  }

  // Write updated README.md
  await Deno.writeTextFile("README.md", newReadme);

  console.log("Infrastructure table generated successfully!");
  console.log("\nGenerated table preview:");
  console.log(tableContent);
}

if (import.meta.main) {
  main();
}
